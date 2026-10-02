# ─────────────────────────────────────────────────────────────────────────────
# fetch_from_kms.sh — how the Redis server reads its secrets from kms (sourced)
#
# Used by     start.sh — you do not run it yourself
#
# Use         source connect_external/kms/fetch_from_kms.sh
#             kms_get mycache-redis mycache/redis REDIS_PASSWORD || exit 1
#
# Calls       1. GET  /v1/sys/health               200 unsealed · 503 sealed
#             2. POST /v1/auth/approle/login       role_id + secret_id → 1-hour token
#             3. GET  /v1/kv/data/mycache/redis    → REDIS_PASSWORD
#             4. POST /v1/auth/token/revoke-self   token thrown away
#
# Result      each KEY exported — in memory only, never printed, never a file
#
# First time  not signed up yet + run by hand in a terminal → signs up ONCE by itself (kms
#             owner's password). In startup / no terminal → a clear message, no question.
#
# Errors      sealed / down / no access / key missing → clear message, return 1 (no fallback)
#
# Settings    .env  KMS_URL          default http://127.0.0.1:8110 (test http · prod https)
#             .env  KMS_APPROLE_DIR  default connect_external/kms/credentials
# ─────────────────────────────────────────────────────────────────────────────

kms_get() {
    local role="${1:-}" path="${2:-}"; shift 2 2>/dev/null || true
    [ -n "$role" ] && [ -n "$path" ] && [ $# -gt 0 ] \
        || { echo "[ERROR] usage: kms_get <approle> <kv path> <KEY>…" >&2; return 1; }
    local url="${KMS_URL:-http://127.0.0.1:8110}" ws d code tok body k v adir
    ws="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
    # this client's own login-file folder (local: never changes the caller's KMS_APPROLE_DIR)
    adir="${KMS_APPROLE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/credentials}"
    d="$adir/$role"

    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url/v1/sys/health" 2>/dev/null)"
    case "$code" in
        200|429|472|473) ;;
        503) echo "[ERROR] kms is SEALED — unseal it (startup prompt or http://127.0.0.1:8110/ui), then try again" >&2; return 1 ;;
        501) echo "[ERROR] kms is not initialised yet" >&2; return 1 ;;
        *)   echo "[ERROR] kms is not reachable at $url (health ${code:-none})" >&2; return 1 ;;
    esac
    # Not signed up yet → sign up ONCE right here (asks the kms owner's password) — but only when
    # run by hand in a terminal: never inside startup / shutdown (SVC_RUN is set by the workspace's
    # svcmgt), never without a terminal. KMS_AUTO_REGISTER=1 forces it (tests).
    if [ ! -r "$d/role_id" ] || [ ! -r "$d/secret_id" ]; then
        if [ -z "${SVC_RUN:-}" ] && { [ -t 0 ] || [ "${KMS_AUTO_REGISTER:-}" = 1 ]; }; then
            echo "[INFO] $role is not signed up with kms yet — signing up once (kms owner's password)" >&2
            KMS_APPROLE_DIR="$adir" bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/signup_with_kms.sh" >&2 || return 1
        else
            echo "[ERROR] $role is not signed up with kms yet — run this component's start by hand once (it asks the kms password), or: bash connect_external/kms/signup_with_kms.sh" >&2; return 1
        fi
    fi

    tok="$(python3 -c 'import sys,json; print(json.dumps({"role_id":open(sys.argv[1]).read().strip(),"secret_id":open(sys.argv[2]).read().strip()}))' \
            "$d/role_id" "$d/secret_id" \
        | curl -s -X POST --data @- "$url/v1/auth/approle/login" \
        | python3 -c 'import sys,json; print((json.load(sys.stdin).get("auth") or {}).get("client_token",""))' 2>/dev/null)"
    [ -n "$tok" ] || { echo "[ERROR] kms refused the login as $role (wrong / revoked secret_id, or not from this PC)" >&2; return 1; }

    body="$(curl -s -H @<(printf 'X-Vault-Token: %s\n' "$tok") "$url/v1/kv/data/$path")"
    curl -s -o /dev/null -X POST -H @<(printf 'X-Vault-Token: %s\n' "$tok") "$url/v1/auth/token/revoke-self"
    unset tok
    if ! printf '%s' "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance((d.get("data") or {}).get("data"),dict) else 1)' 2>/dev/null; then
        echo "[ERROR] kms: $role may not read kv/$path, or it is empty" >&2; unset body; return 1
    fi
    for k in "$@"; do
        printf '%s' "$body" | python3 -c 'import sys,json; sys.exit(0 if sys.argv[1] in json.load(sys.stdin)["data"]["data"] else 1)' "$k" \
            || { echo "[ERROR] kms: kv/$path has no key $k" >&2; unset body; return 1; }
    done
    for k in "$@"; do
        v="$(printf '%s' "$body" | python3 -c 'import sys,json; sys.stdout.write(json.load(sys.stdin)["data"]["data"][sys.argv[1]])' "$k")"
        printf -v "$k" '%s' "$v"; export "$k"
    done
    unset body v
    return 0
}
