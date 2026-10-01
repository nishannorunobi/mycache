# kms_secrets.sh — mycache's OWN client for kms (sourced by start.sh and cache-agent/host_start.sh).
# mycache uses no file of the kms project: it only makes network calls to the kms HTTP API.
#     source kms_secrets.sh
#     kms_get <approle> <kv path> <KEY>…      e.g.  kms_get mycache-redis mycache/redis REDIS_PASSWORD
# The contract with kms (see kms's README, "API contract"):
#   GET  /v1/sys/health                   200 = unsealed · 503 = sealed · 501 = not initialised
#   POST /v1/auth/approle/login           {role_id, secret_id} → 1-hour token
#   GET  /v1/kv/data/<kv path>            header X-Vault-Token → {"data":{"data":{KEY: value}}}
#   POST /v1/auth/token/revoke-self       the token is thrown away right after reading
# Login files: <KMS_APPROLE_DIR>/<approle>/{role_id,secret_id} — default the workspace's
# mountspace/secrets/kms/approle (written once by the owner when mycache was added to kms).
# Exports each KEY (value only in memory, nothing printed). kms sealed / down / no access /
# key missing → clear error, return 1, nothing exported — no fallback to a secret file.
# Secrets never become process arguments (bodies via stdin, token via a file descriptor).

kms_get() {
    local role="${1:-}" path="${2:-}"; shift 2 2>/dev/null || true
    [ -n "$role" ] && [ -n "$path" ] && [ $# -gt 0 ] \
        || { echo "[ERROR] usage: kms_get <approle> <kv path> <KEY>…" >&2; return 1; }
    local url="${KMS_URL:-http://127.0.0.1:8110}" ws d code tok body k v
    ws="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
    d="${KMS_APPROLE_DIR:-$ws/mountspace/secrets/kms/approle}/$role"

    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url/v1/sys/health" 2>/dev/null)"
    case "$code" in
        200|429|472|473) ;;
        503) echo "[ERROR] kms is SEALED — unseal it (startup prompt or http://127.0.0.1:8110/ui), then try again" >&2; return 1 ;;
        501) echo "[ERROR] kms is not initialised yet" >&2; return 1 ;;
        *)   echo "[ERROR] kms is not reachable at $url (health ${code:-none})" >&2; return 1 ;;
    esac
    [ -r "$d/role_id" ] && [ -r "$d/secret_id" ] \
        || { echo "[ERROR] no kms login files for $role in $d — the owner adds mycache to kms first" >&2; return 1; }

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
