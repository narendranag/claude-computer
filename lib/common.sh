# shellcheck shell=bash disable=SC2034
# Shared helpers for bin/ scripts. Source, don't execute.
# Written for bash 3.2 (the macOS system bash): no associative arrays, no mapfile.

# Exit codes used across bin/
readonly EX_OK=0
readonly EX_FAIL=1        # the check ran and found a problem / the call failed
readonly EX_USAGE=2       # bad arguments
readonly EX_DEPS=3        # a required tool is missing
readonly EX_LOCKED=4      # Bitwarden is locked or not logged in
readonly EX_CONFIG=5      # missing config / map / secret item

CC_ROOT="${CC_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export CC_ROOT

# Bitwarden item names are "<prefix><name>", e.g. "claude-computer/tavily".
CC_BW_PREFIX="${CC_BW_PREFIX:-claude-computer/}"

cc_host() {
  if command -v scutil >/dev/null 2>&1; then
    scutil --get LocalHostName 2>/dev/null || hostname -s
  else
    hostname -s
  fi
}

cc_is_macos() { [ "$(uname -s)" = "Darwin" ]; }

cc_err()  { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; }
cc_die()  { local code="$1"; shift; cc_err "$*"; exit "$code"; }
cc_info() { printf '%s\n' "$*" >&2; }

cc_need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || cc_die "$EX_DEPS" "missing dependency: $t"
  done
}

# Print --help text: the leading comment block of the calling script, minus '# '.
cc_usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
}

cc_wants_help() {
  local a
  for a in "$@"; do
    case "$a" in -h|--help) cc_usage; exit "$EX_OK" ;; esac
  done
}

# ---- Bitwarden session ---------------------------------------------------
# The session token is never written to a persistent plaintext file:
#   macOS  → login Keychain (cleared by `secrets-unlock --lock`)
#   Linux  → $XDG_RUNTIME_DIR (tmpfs, per-user, gone at logout), mode 600
# The token is never an argument to any process: writes go through `security -i` (stdin),
# reads come back on stdout. Only the item's service name is ever on a command line.

readonly _CC_KC_SERVICE="claude-computer-bw-session"

_cc_runtime_file() { printf '%s/claude-computer-bw-session' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; }

cc_session_load() {
  [ -n "${BW_SESSION:-}" ] && return 0
  local s=""
  if cc_is_macos; then
    s="$(security find-generic-password -a "$USER" -s "$_CC_KC_SERVICE" -w 2>/dev/null || true)"
  else
    local f; f="$(_cc_runtime_file)"
    [ -r "$f" ] && s="$(cat "$f")"
  fi
  [ -n "$s" ] && export BW_SESSION="$s"
  return 0
}

cc_session_store() {
  local s="$1"
  if cc_is_macos; then
    # `security ... -w "$s"` would put the token in argv, where any process can read it
    # with `ps` — the same rule that keeps keys off curl's command line. `security -i`
    # reads its commands from stdin instead, so argv is just "security -i".
    # printf is a shell builtin, so the token never becomes another process's argument.
    local q="$s"
    q="${q//\\/\\\\}"; q="${q//\"/\\\"}"   # the -i parser is quote-aware; escape what would end the string
    printf 'add-generic-password -U -a "%s" -s "%s" -w "%s"\n' "$USER" "$_CC_KC_SERVICE" "$q" |
      security -i >/dev/null
  else
    local f; f="$(_cc_runtime_file)"
    ( umask 077; printf '%s' "$s" > "$f" )
  fi
}

cc_session_clear() {
  if cc_is_macos; then
    security delete-generic-password -a "$USER" -s "$_CC_KC_SERVICE" >/dev/null 2>&1 || true
  else
    rm -f "$(_cc_runtime_file)"
  fi
}

# Prints: unauthenticated | locked | unlocked
cc_bw_status() {
  command -v bw >/dev/null 2>&1 || { echo "missing"; return; }
  cc_session_load
  bw status 2>/dev/null | jq -r '.status // "unauthenticated"' 2>/dev/null || echo "unauthenticated"
}

cc_require_unlocked() {
  cc_need bw jq
  case "$(cc_bw_status)" in
    unlocked) return 0 ;;
    unauthenticated) cc_die "$EX_LOCKED" "Bitwarden not logged in. Run: bw login" ;;
    *) cc_die "$EX_LOCKED" "Bitwarden is locked. Run: secrets-unlock (in a terminal)" ;;
  esac
}

# cc_secret <name>            → password field of item "<prefix><name>"
# cc_secret <name> <field>    → custom field <field>
# cc_secret <name> username   → username field
# cc_secret <name> notes      → secure-note body
cc_secret() {
  local item="${CC_BW_PREFIX}$1" field="${2:-password}" v
  cc_require_unlocked
  case "$field" in
    password|username) v="$(bw get "$field" "$item" 2>/dev/null)" ;;
    notes)    v="$(bw get notes "$item" 2>/dev/null)" ;;
    *)        v="$(bw get item "$item" 2>/dev/null | jq -r --arg f "$field" '.fields[]? | select(.name==$f) | .value')" ;;
  esac
  [ -n "$v" ] || cc_die "$EX_CONFIG" "Bitwarden item '$item' has no '$field'. See docs/SECRETS.md"
  printf '%s' "$v"
}

# ---- HTTP ---------------------------------------------------------------
# cc_curl "<header line with secret>" [curl args...]
# The secret header goes through curl's config on stdin, so it never appears in `ps`.
cc_curl() {
  local header="$1"; shift
  printf 'header = "%s"\n' "$header" | curl -sS --fail-with-body --max-time "${CC_HTTP_TIMEOUT:-60}" -K - "$@"
}

# ---- rclone remotes from Bitwarden --------------------------------------
# No rclone.conf with keys on disk: remotes are defined through environment variables
# for the lifetime of one script.
#   r2:       Cloudflare R2. Item "claude-computer/r2": username = access key id,
#             password = secret key, fields "endpoint" and "bucket".
#   rescrypt: rclone crypt over r2:<bucket>/resources. Item "claude-computer/r2-crypt":
#             password = crypt password, field "salt" = second password.
# After cc_r2_env, "$CC_R2_BUCKET" holds the bucket name.
cc_r2_env() {
  cc_need rclone
  export RCLONE_CONFIG_R2_TYPE=s3
  export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  export RCLONE_CONFIG_R2_ACL=private
  export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
  RCLONE_CONFIG_R2_ACCESS_KEY_ID="$(cc_secret r2 username)"; export RCLONE_CONFIG_R2_ACCESS_KEY_ID
  RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$(cc_secret r2)"; export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY
  RCLONE_CONFIG_R2_ENDPOINT="$(cc_secret r2 endpoint)"; export RCLONE_CONFIG_R2_ENDPOINT
  CC_R2_BUCKET="$(cc_secret r2 bucket)"; export CC_R2_BUCKET
}

cc_crypt_env() {
  cc_r2_env
  export RCLONE_CONFIG_RESCRYPT_TYPE=crypt
  export RCLONE_CONFIG_RESCRYPT_REMOTE="r2:$CC_R2_BUCKET/resources"
  export RCLONE_CONFIG_RESCRYPT_FILENAME_ENCRYPTION=standard
  export RCLONE_CONFIG_RESCRYPT_DIRECTORY_NAME_ENCRYPTION=true
  RCLONE_CONFIG_RESCRYPT_PASSWORD="$(cc_secret r2-crypt | rclone obscure -)"; export RCLONE_CONFIG_RESCRYPT_PASSWORD
  RCLONE_CONFIG_RESCRYPT_PASSWORD2="$(cc_secret r2-crypt salt | rclone obscure -)"; export RCLONE_CONFIG_RESCRYPT_PASSWORD2
}

# Ask a yes/no question on the terminal. Non-interactive → no.
cc_confirm() {
  [ -t 0 ] || return 1
  local reply
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
