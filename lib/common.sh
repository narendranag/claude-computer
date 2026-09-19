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

SM_ROOT="${SM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export SM_ROOT

# Bitwarden item names are "<prefix><name>", e.g. "system-manager/tavily".
SM_BW_PREFIX="${SM_BW_PREFIX:-system-manager/}"

sm_host() {
  if command -v scutil >/dev/null 2>&1; then
    scutil --get LocalHostName 2>/dev/null || hostname -s
  else
    hostname -s
  fi
}

sm_is_macos() { [ "$(uname -s)" = "Darwin" ]; }

sm_err()  { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; }
sm_die()  { local code="$1"; shift; sm_err "$*"; exit "$code"; }
sm_info() { printf '%s\n' "$*" >&2; }

sm_need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || sm_die "$EX_DEPS" "missing dependency: $t"
  done
}

# Print --help text: the leading comment block of the calling script, minus '# '.
sm_usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
}

sm_wants_help() {
  local a
  for a in "$@"; do
    case "$a" in -h|--help) sm_usage; exit "$EX_OK" ;; esac
  done
}

# ---- Bitwarden session ---------------------------------------------------
# The session token is never written to a persistent plaintext file:
#   macOS  → login Keychain (cleared by `secrets-unlock --lock`)
#   Linux  → $XDG_RUNTIME_DIR (tmpfs, per-user, gone at logout), mode 600
# The token is never an argument to any process: writes go through `security -i` (stdin),
# reads come back on stdout. Only the item's service name is ever on a command line.

readonly _SM_KC_SERVICE="system-manager-bw-session"

_sm_runtime_file() { printf '%s/system-manager-bw-session' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; }

sm_session_load() {
  [ -n "${BW_SESSION:-}" ] && return 0
  local s=""
  if sm_is_macos; then
    s="$(security find-generic-password -a "$USER" -s "$_SM_KC_SERVICE" -w 2>/dev/null || true)"
  else
    local f; f="$(_sm_runtime_file)"
    [ -r "$f" ] && s="$(cat "$f")"
  fi
  [ -n "$s" ] && export BW_SESSION="$s"
  return 0
}

sm_session_store() {
  local s="$1"
  if sm_is_macos; then
    # `security ... -w "$s"` would put the token in argv, where any process can read it
    # with `ps` — the same rule that keeps keys off curl's command line. `security -i`
    # reads its commands from stdin instead, so argv is just "security -i".
    # printf is a shell builtin, so the token never becomes another process's argument.
    local q="$s"
    q="${q//\\/\\\\}"; q="${q//\"/\\\"}"   # the -i parser is quote-aware; escape what would end the string
    printf 'add-generic-password -U -a "%s" -s "%s" -w "%s"\n' "$USER" "$_SM_KC_SERVICE" "$q" |
      security -i >/dev/null
  else
    local f; f="$(_sm_runtime_file)"
    ( umask 077; printf '%s' "$s" > "$f" )
  fi
}

sm_session_clear() {
  if sm_is_macos; then
    security delete-generic-password -a "$USER" -s "$_SM_KC_SERVICE" >/dev/null 2>&1 || true
  else
    rm -f "$(_sm_runtime_file)"
  fi
}

# Prints: unauthenticated | locked | unlocked
sm_bw_status() {
  command -v bw >/dev/null 2>&1 || { echo "missing"; return; }
  sm_session_load
  bw status 2>/dev/null | jq -r '.status // "unauthenticated"' 2>/dev/null || echo "unauthenticated"
}

sm_require_unlocked() {
  sm_need bw jq
  case "$(sm_bw_status)" in
    unlocked) return 0 ;;
    unauthenticated) sm_die "$EX_LOCKED" "Bitwarden not logged in. Run: bw login" ;;
    *) sm_die "$EX_LOCKED" "Bitwarden is locked. Run: secrets-unlock (in a terminal)" ;;
  esac
}

# sm_secret <name>            → password field of item "<prefix><name>"
# sm_secret <name> <field>    → custom field <field>
# sm_secret <name> username   → username field
# sm_secret <name> notes      → secure-note body
sm_secret() {
  local item="${SM_BW_PREFIX}$1" field="${2:-password}" v
  sm_require_unlocked
  case "$field" in
    password|username) v="$(bw get "$field" "$item" 2>/dev/null)" ;;
    notes)    v="$(bw get notes "$item" 2>/dev/null)" ;;
    *)        v="$(bw get item "$item" 2>/dev/null | jq -r --arg f "$field" '.fields[]? | select(.name==$f) | .value')" ;;
  esac
  [ -n "$v" ] || sm_die "$EX_CONFIG" "Bitwarden item '$item' has no '$field'. See docs/SECRETS.md"
  printf '%s' "$v"
}

# ---- HTTP ---------------------------------------------------------------
# sm_curl "<header line with secret>" [curl args...]
# The secret header goes through curl's config on stdin, so it never appears in `ps`.
sm_curl() {
  local header="$1"; shift
  printf 'header = "%s"\n' "$header" | curl -sS --fail-with-body --max-time "${SM_HTTP_TIMEOUT:-60}" -K - "$@"
}

# ---- rclone remotes from Bitwarden --------------------------------------
# No rclone.conf with keys on disk: remotes are defined through environment variables
# for the lifetime of one script.
#   r2:       Cloudflare R2. Item "system-manager/r2": username = access key id,
#             password = secret key, fields "endpoint" and "bucket".
#   rescrypt: rclone crypt over r2:<bucket>/resources. Item "system-manager/r2-crypt":
#             password = crypt password, field "salt" = second password.
# After sm_r2_env, "$SM_R2_BUCKET" holds the bucket name.
sm_r2_env() {
  sm_need rclone
  export RCLONE_CONFIG_R2_TYPE=s3
  export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
  export RCLONE_CONFIG_R2_ACL=private
  export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
  RCLONE_CONFIG_R2_ACCESS_KEY_ID="$(sm_secret r2 username)"; export RCLONE_CONFIG_R2_ACCESS_KEY_ID
  RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$(sm_secret r2)"; export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY
  RCLONE_CONFIG_R2_ENDPOINT="$(sm_secret r2 endpoint)"; export RCLONE_CONFIG_R2_ENDPOINT
  SM_R2_BUCKET="$(sm_secret r2 bucket)"; export SM_R2_BUCKET
}

sm_crypt_env() {
  sm_r2_env
  export RCLONE_CONFIG_RESCRYPT_TYPE=crypt
  export RCLONE_CONFIG_RESCRYPT_REMOTE="r2:$SM_R2_BUCKET/resources"
  export RCLONE_CONFIG_RESCRYPT_FILENAME_ENCRYPTION=standard
  export RCLONE_CONFIG_RESCRYPT_DIRECTORY_NAME_ENCRYPTION=true
  RCLONE_CONFIG_RESCRYPT_PASSWORD="$(sm_secret r2-crypt | rclone obscure -)"; export RCLONE_CONFIG_RESCRYPT_PASSWORD
  RCLONE_CONFIG_RESCRYPT_PASSWORD2="$(sm_secret r2-crypt salt | rclone obscure -)"; export RCLONE_CONFIG_RESCRYPT_PASSWORD2
}

# Ask a yes/no question on the terminal. Non-interactive → no.
sm_confirm() {
  [ -t 0 ] || return 1
  local reply
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
