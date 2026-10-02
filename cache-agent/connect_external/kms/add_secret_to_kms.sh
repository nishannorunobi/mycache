#!/bin/bash
# cache-agent/connect_external/kms/add_secret_to_kms.sh — store a NEW (or changed) secret of the
# CACHE-AGENT in kms, instead of writing it into a config file.
#     bash cache-agent/connect_external/kms/add_secret_to_kms.sh <KEY>     e.g.  … NEW_API_KEY
# Asks for the kms owner's password, then the value (both hidden). Stores it in kv/mycache/cache-agent
# next to the keys already there (they are kept). Nothing is printed except the version number.
# Then read it in host_start.sh like the others:  kms_get mycache-cache-agent mycache/cache-agent <KEY>
# (mycache-cache-agent may already read kv/mycache/cache-agent — no new sign-up needed.)
# Shared keys (kv/shared/…) are not the agent's own — they are not written here.
# Over the kms HTTP API only — no kms file is used. NO mirror logging on purpose.
# Exit 0 = stored; 1 = failed, nothing changed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"
[ -f "$ENV_FILE" ] && source <(grep -E '^KMS_(URL|APPROLE_DIR)=' "$ENV_FILE")
URL="${KMS_URL:-http://127.0.0.1:8110}"
OWNER="${KMS_OWNER:-nishan}"
KPATH="mycache/cache-agent"                           # the agent's own place in kms

KEY="${1:-}"
[[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "usage: add_secret_to_kms.sh <KEY>   (letters, digits, _)" >&2; exit 2; }
h="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/v1/sys/health")"
[ "$h" = 200 ] || { echo "[ERROR] kms at $URL is not running + unsealed (health ${h:-none})" >&2; exit 1; }

read -r -s -p "kms password for $OWNER (hidden): " pw; echo >&2
TOKEN="$(printf '%s' "$pw" | python3 -c 'import sys,json; print(json.dumps({"password": sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$URL/v1/auth/userpass/login/$OWNER" \
    | python3 -c 'import sys,json; print((json.load(sys.stdin).get("auth") or {}).get("client_token",""))' 2>/dev/null)"
unset pw
[ -n "$TOKEN" ] || { echo "[ERROR] kms login failed for $OWNER" >&2; exit 1; }
trap 'curl -s -o /dev/null -X POST -H @<(printf "X-Vault-Token: %s\n" "$TOKEN") "$URL/v1/auth/token/revoke-self"; unset TOKEN VAL' EXIT

read -r -s -p "Value for $KEY (hidden): " VAL; echo >&2
[ -n "$VAL" ] || { echo "[ERROR] empty value — nothing stored" >&2; exit 1; }

# keys already at kv/mycache/cache-agent (kept) + the new one — both via stdin, never argv / env
CUR="$(curl -s -H @<(printf 'X-Vault-Token: %s\n' "$TOKEN") "$URL/v1/kv/data/$KPATH" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps((d.get("data") or {}).get("data") or {}))' 2>/dev/null)"
[ -n "$CUR" ] || CUR='{}'
ver="$(printf '%s\n%s' "$CUR" "$VAL" | python3 -c 'import sys,json
cur=json.loads(sys.stdin.readline()); cur[sys.argv[1]]=sys.stdin.read(); print(json.dumps({"data": cur}))' "$KEY" \
    | curl -s -X POST -H @<(printf 'X-Vault-Token: %s\n' "$TOKEN") --data @- "$URL/v1/kv/data/$KPATH" \
    | python3 -c 'import sys,json; print(((json.load(sys.stdin).get("data")) or {}).get("version",""))' 2>/dev/null)"
unset CUR VAL
[ -n "$ver" ] || { echo "[ERROR] kms refused the write" >&2; exit 1; }
echo -e "\033[32m[  OK  ]\033[0m kv/$KPATH  $KEY stored (version $ver) — read it with: kms_get mycache-cache-agent $KPATH $KEY"
