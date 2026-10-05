#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# add_new_secret_to_kms.sh — a NEW secret of the cache-agent → kms
#
# What for    A new password / key / token for the agent goes into kms — never into agent.conf.
#
# Who         The kms owner (needs the kms password). The agent itself can only read.
#
# How         bash cache-agent/connect_external/kms/add_new_secret_to_kms.sh
#             (it asks: key name · your kms password · the value — all but the name hidden)
#
# Steps       1. store the value in kms (other keys kept; same name again = new version)
#             2. write the line in agent.conf:  <KEY>=<its kms address>  (added, or updated)
#
# Output      Key name: NEW_API_KEY
#             kms password for nishan (hidden): ********
#             Value for NEW_API_KEY (hidden): ********
#             [  OK  ] kv/<entry>  NEW_API_KEY stored (version 3)
#             [  OK  ] agent.conf  NEW_API_KEY=http://kms-openbao:8200/v1/kv/data/<entry>
#
# Note        A key agent.conf already points at (REDIS_PASSWORD → kv/mycache/redis) goes to THAT entry
#             (same name again = a new version); a new key goes to the agent's own kv/mycache/cache-agent.
#
# Also        refresh_random_secrets_to_kms.sh hands the value (KMS_NEW_SECRET_VALUE) and its one kms
#             login (KMS_TOKEN) over by name instead of asking — the only other caller.
#
# Next        restart it — the container fetches the new key at start
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail
# a hidden prompt goes to the terminal itself — under start.sh's mirror logging stderr is a pipe that shows a line only after Enter
ask() { { printf '%s' "$1" > /dev/tty; } 2>/dev/null || printf '%s' "$1" >&2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"
URL="${KMS_URL:-http://127.0.0.1:8110}"                     # kms as seen from THIS PC
OWNER="${KMS_OWNER:-nishan}"
OWN_PATH="mycache/cache-agent"                        # the agent's own entry for NEW keys

KEY="${1:-}"
[ -n "$KEY" ] || read -r -p "Key name (e.g. NEW_API_KEY): " KEY
[[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "[ERROR] key name: letters, digits and _ only (got '$KEY')" >&2; exit 2; }
# where it lives: the entry agent.conf already names for this key (REDIS_PASSWORD → mycache/redis), else the agent's own entry
KPATH="$(grep -E "^$KEY=https?://" "$ENV_FILE" 2>/dev/null | grep -oE '/v1/kv/data/[^ ]+' | head -1 | sed 's#^/v1/kv/data/##')"
KPATH="${KPATH:-$OWN_PATH}"
h="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/v1/sys/health")"
[ "$h" = 200 ] || { echo "[ERROR] kms at $URL is not running + unsealed (health ${h:-none})" >&2; exit 1; }

if [ -n "${KMS_TOKEN:-}" ]; then TOKEN="$KMS_TOKEN"; MINE=                    # handed over by refresh_random_secrets_to_kms.sh (one login, several keys)
else
    ask "kms password for $OWNER (hidden): "; read -r -s pw; echo >&2
    TOKEN="$(printf '%s' "$pw" | python3 -c 'import sys,json; print(json.dumps({"password": sys.stdin.read()}))' \
        | curl -s -X POST --data @- "$URL/v1/auth/userpass/login/$OWNER" \
        | python3 -c 'import sys,json; print((json.load(sys.stdin).get("auth") or {}).get("client_token",""))' 2>/dev/null)"
    unset pw; MINE=1
    [ -n "$TOKEN" ] || { echo "[ERROR] kms login failed for $OWNER" >&2; exit 1; }
fi
trap '[ -n "$MINE" ] && curl -s -o /dev/null -X POST -H @<(printf "X-Vault-Token: %s\n" "$TOKEN") "$URL/v1/auth/token/revoke-self"; unset TOKEN VAL' EXIT

if [ -n "${KMS_NEW_SECRET_VALUE:-}" ]; then VAL="$KMS_NEW_SECRET_VALUE"; unset KMS_NEW_SECRET_VALUE     # handed over by name (refresh script)
else ask "Value for $KEY (hidden): "; read -r -s VAL; echo >&2; fi
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
echo -e "\033[32m[  OK  ]\033[0m kv/$KPATH  $KEY stored (version $ver)"

# the config line: <KEY>=<kms address> — the same kms as the lines already there
BASE="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=https?://' "$ENV_FILE" 2>/dev/null | grep -oE 'https?://[^/ ]+/v1/kv/' | head -1)"   # real lines only, not comments
BASE="${BASE:-http://kms-openbao:8200/v1/kv/}"
ADDR="${BASE}data/$KPATH"
python3 - "$ENV_FILE" "$KEY" "$ADDR" <<'PY2'
import sys, re, os
path, key, addr = sys.argv[1:]
lines = open(path).read().splitlines() if os.path.exists(path) else []
pat = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
hit = [i for i, l in enumerate(lines) if pat.match(l)]
if hit: lines[hit[0]] = f"{key}={addr}"
else:   lines.append(f"{key}={addr}")
open(path, "w").write("\n".join(lines) + "\n")
PY2
echo -e "\033[32m[  OK  ]\033[0m $(basename "$ENV_FILE")  $KEY=$ADDR"
