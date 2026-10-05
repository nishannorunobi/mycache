#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# refresh_random_secrets_to_kms.sh — a new RANDOM Redis password: kms + Redis, nothing shown
#
# What for    Rotation without flags and without seeing a value: REDIS_PASSWORD gets a fresh
#             random value in kms, then Redis restarts with it (the cache-agent is the entry
#             point: it reads kms at start and follows a refusal by asking kms again).
#
# Who         The kms owner (asks the kms password ONCE). Values are never printed.
#
# How         bash cache-agent/connect_external/kms/refresh_random_secrets_to_kms.sh
#
# Steps       1. REDIS_PASSWORD=<kms address> from agent.conf → its entry (mycache/redis)
#             2. kms login once (your password) · the current value must still work in Redis
#             3. random 40 chars → add_new_secret_to_kms.sh (value + login handed over by name)
#             4. docker restart mycache-redis → the agent writes the new requirepass, Redis starts
#             5. check: the new password works, the old one is refused
#
# Output      kms password for nishan (hidden): ********
#             [  OK  ] kv/mycache/redis  REDIS_PASSWORD stored (version 2)
#             [  OK  ] Redis has the new password — the old one is refused
#               Update everyone else who uses it: Plane — projectspace/mydocs/.env REDIS_URL (then restart Plane)
#
# Errors      "kms and Redis disagree already" — the current kms value is refused by Redis: fix that
#             first (docker logs mycache-redis | grep agent). A new value refused → the old one is
#             written back to kms, nothing else changes.
#
# Next        clients that keep a copy of the password need the new one (Plane .env REDIS_URL) — until
#             their own kms stories; a client that reads kms itself only needs a restart.
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# a hidden prompt goes to the terminal itself — under start.sh's mirror logging stderr is a pipe that shows a line only after Enter
ask() { { printf '%s' "$1" > /dev/tty; } 2>/dev/null || printf '%s' "$1" >&2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="$(cd "$HERE/../.." && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$AGENT/agent.conf}"
URL="${KMS_URL:-http://127.0.0.1:8110}"                   # kms as seen from THIS PC
OWNER="${KMS_OWNER:-nishan}"
C="${REDIS_CONTAINER:-mycache-redis}"
KEY=REDIS_PASSWORD
ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*" >&2; }
KPATH="$(grep -E "^$KEY=https?://" "$ENV_FILE" 2>/dev/null | grep -oE '/v1/kv/data/[^ ]+' | head -1 | sed 's#^/v1/kv/data/##')"
[ -n "$KPATH" ] || { bad "$KEY is not a kms address in $(basename "$ENV_FILE")"; exit 1; }
docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null | grep -q true || { bad "Redis ($C) is not running — start it first: bash start.sh"; exit 1; }
h="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/v1/sys/health")"
case "$h" in 200) ;; 503) bad "kms is SEALED — unseal it first"; exit 1 ;; *) bad "kms is not reachable at $URL (health ${h:-none})"; exit 1 ;; esac
# AUTH check: the password reaches redis-cli by env inside the container, never on a command line
redis_auth() { printf '%s\n' "$1" | docker exec -i "$C" sh -c 'read -r p; REDISCLI_AUTH="$p" redis-cli ping' 2>/dev/null | grep -qx PONG; }

# one kms login for everything
if [ -z "${KMS_TOKEN:-}" ]; then
    ask "kms password for $OWNER (hidden): "; read -r -s pw; echo >&2
    KMS_TOKEN="$(printf '%s' "$pw" | python3 -c 'import sys,json; print(json.dumps({"password": sys.stdin.read()}))' \
        | curl -s -X POST --data @- "$URL/v1/auth/userpass/login/$OWNER" \
        | python3 -c 'import sys,json; print((json.load(sys.stdin).get("auth") or {}).get("client_token",""))' 2>/dev/null)"
    unset pw; MINE=1
    [ -n "$KMS_TOKEN" ] || { bad "kms login failed for $OWNER"; exit 1; }
else MINE=; fi
export KMS_TOKEN
trap '[ -n "$MINE" ] && curl -s -o /dev/null -X POST -H @<(printf "X-Vault-Token: %s\n" "$KMS_TOKEN") "$URL/v1/auth/token/revoke-self"; unset KMS_TOKEN OLD NEW' EXIT
OLD="$(curl -s -H @<(printf 'X-Vault-Token: %s\n' "$KMS_TOKEN") "$URL/v1/kv/data/$KPATH" \
    | python3 -c 'import sys,json; d=((json.load(sys.stdin).get("data") or {}).get("data") or {}); sys.stdout.write(d.get(sys.argv[1]) or "")' "$KEY")"
[ -z "$OLD" ] || redis_auth "$OLD" || { bad "kms and Redis disagree already (kms's current password is refused) — fix that first"; exit 1; }
NEW="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 40)"
KMS_NEW_SECRET_VALUE="$NEW" bash "$HERE/add_new_secret_to_kms.sh" "$KEY" || { bad "kms did not take the new value — nothing changed"; exit 1; }

# Redis takes it at start: restart the container (the agent fetches kms, writes /run/redis.conf)
docker restart "$C" >/dev/null || { bad "could not restart $C"; exit 1; }
for _ in $(seq 1 60); do redis_auth "$NEW" && break; sleep 1; done
if redis_auth "$NEW" && ! { [ -n "$OLD" ] && redis_auth "$OLD"; }; then
    ok "Redis has the new password — the old one is refused"
    echo "  The cache-agent follows by itself (it asks kms). Update everyone else who uses it: Plane — projectspace/mydocs/.env REDIS_URL (then restart Plane)"
    exit 0
fi
bad "Redis did not take the new password — writing the old one back to kms"
[ -n "$OLD" ] && KMS_NEW_SECRET_VALUE="$OLD" bash "$HERE/add_new_secret_to_kms.sh" "$KEY" >/dev/null && docker restart "$C" >/dev/null \
    && bad "kms is back to the old password — nothing changed" || bad "could NOT put kms back — fix by hand (docker logs $C | grep agent)"
exit 1
