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

# ---- Secrets: sops + age --------------------------------------------------
# One sops file, secrets/secrets.yaml, encrypted to every manager's age key and the paper
# backup key. Its key names are plaintext; every value is encrypted. A secret is addressed as
# <name>.<field> (`tavily.api_key`), the sops path ["name"]["field"].
# Values never become a process argument: reads come back on stdout into a variable, writes
# go to `sops set --value-stdin` through a pipe. Claude never decrypts; only these helpers do.
CC_SECRETS_FILE="${CC_SECRETS_FILE:-$CC_ROOT/secrets/secrets.yaml}"
CC_SOPS_CONFIG="${CC_SOPS_CONFIG:-$CC_ROOT/.sops.yaml}"
# sops's own default on macOS is ~/Library/Application Support/sops/age/keys.txt. One path on
# every OS, set here because launchd jobs and hooks never read ~/.zshenv.
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE
readonly CC_SOPS_MIN="3.11.0" # the first release with `sops set --value-stdin`

# cc_secret_name_ok <name> <field> — lowercase-ish names only, so a path can't be injected.
cc_secret_name_ok() {
  case "$1" in "" | *[!A-Za-z0-9_-]*) return 1 ;; esac
  case "$2" in "" | *[!A-Za-z0-9_-]*) return 1 ;; esac
  return 0
}

# cc_secrets_list <file> — "<name>.<field><TAB><state>" for every value, without decrypting.
# state: enc (sops ciphertext) · empty ("" — sops leaves empty strings as they are) · plain
# (anything else: a plaintext value, a block scalar, or deeper nesting than name.field).
# Top-level keys other than `sops` are names; their children are fields.
cc_secrets_list() {
  awk '
    function flush() { if (pk != "") print pk "\t" ps; pk = "" }
    /^[[:space:]]*(#|$)/ { next }
    /^[^[:space:]]/ {
      flush(); top = $0; sub(/:.*/, "", top); ind = 0
      v = $0; sub(/^[^:]*:[ ]*/, "", v); sub(/[ ]+#.*$/, "", v)
      if (top != "sops" && v != "" && v != "{}") { pk = top; ps = (v ~ /^ENC\[/) ? "enc" : "plain"; flush() }
      next
    }
    top == "sops" { next }
    {
      match($0, /^[ ]+/); cur = RLENGTH
      if (ind == 0) ind = cur
      if (cur > ind) { if (pk != "") ps = "plain"; next }
      flush()
      line = substr($0, cur + 1)
      k = line; sub(/:.*/, "", k)
      v = line; sub(/^[^:]*:[ ]*/, "", v); sub(/[ ]+#.*$/, "", v)
      if (v ~ /^ENC\[/) s = "enc"
      else if (v == "" || v == "\"\"" || v == "'\'''\''") s = "empty"
      else s = "plain"
      pk = top "." k; ps = s
    }
    END { flush() }
  ' "$1"
}

# cc_secrets_recipients <file> — the age recipients in a sops file's metadata, one per line.
cc_secrets_recipients() {
  awk '/^sops:/ {s = 1; next} /^[^[:space:]]/ {s = 0} s && /recipient:[ ]*age1/ {sub(/.*recipient:[ ]*/, ""); print}' "$1"
}

# cc_age_pub — this machine's age public key, derived from its key file. Empty if none.
cc_age_pub() {
  [ -r "$SOPS_AGE_KEY_FILE" ] || return 0
  age-keygen -y "$SOPS_AGE_KEY_FILE" 2>/dev/null || true
}

# cc_sops_need — sops present and new enough for --value-stdin.
cc_sops_need() {
  cc_need sops
  local v want have i a b
  v="$(sops --disable-version-check --version 2>/dev/null | awk 'NR==1 {print $2}')"
  want="$CC_SOPS_MIN"; have="$v"
  for i in 1 2 3; do
    a="$(printf '%s' "$have" | cut -d. -f"$i")"; b="$(printf '%s' "$want" | cut -d. -f"$i")"
    a="${a%%[!0-9]*}"; b="${b%%[!0-9]*}"
    [ "${a:-0}" -gt "${b:-0}" ] && return 0
    [ "${a:-0}" -lt "${b:-0}" ] && cc_die "$EX_DEPS" "sops ${v:-unknown} is too old: need $CC_SOPS_MIN or newer"
  done
  return 0
}

# cc_sops_get <name> <field> — print one decrypted value (no trailing newline).
# Exit codes: EX_CONFIG not in the store / empty · EX_LOCKED no key, or this key can't open
# the store · EX_FAIL plaintext in the store, or sops failed.
cc_sops_get() {
  local name="$1" field="$2" state v
  cc_secret_name_ok "$name" "$field" || cc_die "$EX_USAGE" "not a secret name: $name.$field (want <name>.<field>)"
  cc_need sops
  [ -f "$CC_SECRETS_FILE" ] || cc_die "$EX_CONFIG" "no secrets store at $CC_SECRETS_FILE. See docs/SECRETS.md"
  state="$(cc_secrets_list "$CC_SECRETS_FILE" | awk -F '\t' -v k="$name.$field" '$1 == k {print $2; exit}')"
  case "$state" in
    enc) ;;
    "" | empty) cc_die "$EX_CONFIG" "secret '$name.$field' is not set. A human runs: secrets set $name.$field (see docs/SECRETS.md)" ;;
    *) cc_die "$EX_FAIL" "secret '$name.$field' is stored unencrypted — see secrets/README.md" ;;
  esac
  [ -r "$SOPS_AGE_KEY_FILE" ] || cc_die "$EX_LOCKED" "no age key at $SOPS_AGE_KEY_FILE. Run: secrets init (see docs/SECRETS.md)"
  if ! v="$(sops decrypt --extract "[\"$name\"][\"$field\"]" "$CC_SECRETS_FILE" 2>/dev/null)"; then
    if cc_secrets_recipients "$CC_SECRETS_FILE" | grep -qxF "$(cc_age_pub)"; then
      cc_die "$EX_FAIL" "sops could not decrypt '$name.$field'"
    fi
    cc_die "$EX_LOCKED" "this machine's age key can't open the store. On a manager: secrets admit $(cc_host)"
  fi
  printf '%s' "$v"
}

# cc_sops_set <name> <field> — store the value read from stdin (trailing newlines dropped).
# The value goes printf → jq → sops through pipes; it is never an argument.
cc_sops_set() {
  local name="$1" field="$2"
  cc_secret_name_ok "$name" "$field" || cc_die "$EX_USAGE" "not a secret name: $name.$field (want <name>.<field>)"
  cc_sops_need
  cc_need jq
  [ -f "$CC_SECRETS_FILE" ] || cc_die "$EX_CONFIG" "no secrets store at $CC_SECRETS_FILE. Run: secrets init --first"
  jq -Rs 'sub("\n+$"; "")' | sops set --value-stdin "$CC_SECRETS_FILE" "[\"$name\"][\"$field\"]" 2>/dev/null ||
    cc_die "$EX_FAIL" "sops could not write '$name.$field' (is this machine a recipient? secrets status)"
}

# cc_remote_visibility <repo dir> — PRIVATE | INTERNAL | PUBLIC for a GitHub origin, NONE with no
# origin, UNKNOWN when it can't be read (no gh, offline, not GitHub).
cc_remote_visibility() {
  local origin slug v
  origin="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  [ -n "$origin" ] || { echo NONE; return 0; }
  command -v gh >/dev/null 2>&1 || { echo UNKNOWN; return 0; }
  slug="$(printf '%s' "$origin" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')"
  v="$(gh repo view "$slug" --json visibility --jq .visibility 2>/dev/null || true)"
  case "$v" in PRIVATE | INTERNAL | PUBLIC) echo "$v" ;; *) echo UNKNOWN ;; esac
}

# cc_env_path <ENV_NAME> — the <name>.<field> an environment variable maps to: a well-known
# name the wrappers already read, else env.<lowercased name>.
cc_env_path() {
  case "$1" in
    TAVILY_API_KEY) echo tavily.api_key ;;
    FIRECRAWL_API_KEY) echo firecrawl.api_key ;;
    JINA_API_KEY) echo jina.api_key ;;
    EXA_API_KEY) echo exa.api_key ;;
    OPENAI_API_KEY) echo openai.api_key ;;
    GOOGLE_MAPS_API_KEY) echo google-maps.api_key ;;
    DUFFEL_API_KEY | DUFFEL_ACCESS_TOKEN) echo duffel.api_key ;;
    TELEGRAM_BOT_TOKEN | TELEGRAM_TOKEN) echo telegram.token ;;
    TELEGRAM_CHAT_ID) echo telegram.chat_id ;;
    R2_ACCESS_KEY_ID) echo r2.access_key_id ;;
    R2_SECRET_ACCESS_KEY) echo r2.secret_access_key ;;
    R2_ENDPOINT) echo r2.endpoint ;;
    R2_BUCKET) echo r2.bucket ;;
    *) printf 'env.%s\n' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" ;;
  esac
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
