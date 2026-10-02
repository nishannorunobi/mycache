#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# add_new_secret_to_kms.sh — a NEW secret of the cache-agent → kms
#
# What for    A new password / key / token for the agent goes into kms — never into agent.conf.
#
# Who         The kms owner (needs the kms password). The agent itself can only read.
#
# How         bash cache-agent/connect_external/kms/add_new_secret_to_kms.sh NEW_AGENT_KEY
#
# Output      kms password for nishan (hidden): ********
#             Value for NEW_AGENT_KEY (hidden): ********
#             [  OK  ] kv/mycache/cache-agent  NEW_AGENT_KEY stored (version 1)
#
# Note        Stored in the agent's own place kv/mycache/cache-agent. Shared keys are not written here.
#
# Next        use it in host_start.sh:
#             kms_get mycache-cache-agent mycache/cache-agent NEW_AGENT_KEY || exit 1
#             then hand it over by name: docker exec -e NEW_AGENT_KEY …
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"
[ -f "$ENV_FILE" ] && source <(grep -E '^KMS_(URL|APPROLE_DIR)=' "$ENV_FILE")
URL="${KMS_URL:-http://127.0.0.1:8110}"
OWNER="${KMS_OWNER:-nishan}"
KPATH="mycache/cache-agent"                           # the agent's own place in kms

KEY="${1:-}"
[[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "usage: add_new_secret_to_kms.sh <KEY>   (letters, digits, _)" >&2; exit 2; }
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
