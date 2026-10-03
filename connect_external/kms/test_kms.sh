#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_kms.sh — automatic tests: mycache gets its secrets from kms
#
# What for    Prove the Redis container fetches its OWN password from kms (.env value =
#             its kms address), the cache-agent fetches its secrets, nothing is printed,
#             and no secret is kept in a file.
#
# Who         Claude (Auto test) — you can run it too; nothing live is touched.
#
# How         bash connect_external/kms/test_kms.sh        (≈1 min)
#
# Steps       a throwaway kms (127.0.0.1:8119, on a throwaway Docker network) + throwaway
#             Redis containers from mycache's own image, running mycache's real
#             docker-compose command and healthcheck
#
# Checks      T0  server + agent sign themselves up (a kms address in .env is never copied)
#             T1  the Redis container fetches REDIS_PASSWORD itself · T9 the agent fetches its own
#             T3  refused outside own paths · T4 Redis password works, wrong refused
#             T5  empty password → Redis refuses to start · T6 password on no command line
#             T7  healthcheck without -a · T8 nothing printed, tracked .env / agent.conf
#                 secret-free, credentials ignored · T11 add_new_secret_to_kms.sh
#             T12 every script has a tidy header + --help · T13 agent uses only its own login
#             T14 no login, in startup: start.sh / host_start.sh → message, nothing started
#             T15 .env lists every key compose needs · T16 a plain value still works
#             T17 the Redis UI gets the password from the RAM volume and connects
#             T2  kms sealed → container stops with SEALED · T10 no test value in logs / git
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

MYCACHE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"          # mycache (this file: connect_external/kms/)
PROJECT="${KMS_PROJECT:-$_WS_ROOT/projectspace/kms}"                     # test-only: the kms image + bootstrap
DOCKERSPACE="$PROJECT/dockerspace"
LOGS="$_WS_ROOT/mountspace/logs/myworkspace/projectspace"
source "$DOCKERSPACE/.env"
T=kms-mycache-test; R=kms-mycache-redis-test; NET=kms-mycache-testnet; U=kms-mycache-ui-test; VOL=kms-mycache-test-secrets
export KMS_URL=http://127.0.0.1:8119
DATA="$(mktemp -d)"; AUDIT="$(mktemp -d)"
export KMS_STATE_DIR="$(mktemp -d)" KMS_SECRETS_DIR="$(mktemp -d)/kms" KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32"
export KMS_APPROLE_DIR="$KMS_SECRETS_DIR/approle"   # where mycache's client looks for its login files
FAIL=0
ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
cleanup() { docker rm -f "$T" "$R" "$U" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; rm -rf "$DATA" "$AUDIT" "$KMS_STATE_DIR" "$(dirname "$KMS_SECRETS_DIR")"; }
trap cleanup EXIT
health() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$KMS_URL/v1/sys/health"; }
j() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
REDIS_IMAGE="mycache-redis:$(grep -E '^REDIS_VERSION=' "$MYCACHE/.env" | cut -d= -f2)"
docker image inspect "$REDIS_IMAGE" >/dev/null 2>&1 || (cd "$MYCACHE" && docker compose build -q redis) || { bad "mycache image $REDIS_IMAGE missing and could not be built"; exit 1; }
# the Redis command + healthcheck exactly as docker compose runs them ($$ → $)
CMD="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(re.search(r"command:\n(?:\s+- .*\n)*?\s+- -c\n\s+- (.*)", r).group(1).replace("$$","$"))')"
HC="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(re.search(r"- CMD-SHELL\n\s+- (.*)", r).group(1).replace("$$","$"))')"
[ -n "$CMD" ] && [ -n "$HC" ] || { bad "could not read the Redis command / healthcheck from mycache's compose"; exit 1; }

# ── throwaway kms: init, unseal, bootstrap, add mycache, seed values ──────────
docker rm -f "$T" "$R" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1
docker network create "$NET" >/dev/null || { bad "test network failed"; exit 1; }
docker run -d --name "$T" --network "$NET" -p 127.0.0.1:8119:8200 --user "$(id -u):$(id -g)" -e SKIP_CHOWN=true \
    -v "$DOCKERSPACE/config:/openbao/config:ro" -v "$DATA:/openbao/data" -v "$AUDIT:/openbao/audit" \
    "$OPENBAO_IMAGE" server >/dev/null || { bad "throwaway kms did not start"; exit 1; }
for _ in $(seq 1 30); do [ "$(health)" = 501 ] && break; sleep 1; done
INIT="$(printf '{"secret_shares":3,"secret_threshold":2}' | curl -s -X PUT --data @- "$KMS_URL/v1/sys/init")"
S1="$(echo "$INIT" | j 'd["keys_base64"][0]')"; S2="$(echo "$INIT" | j 'd["keys_base64"][1]')"; unset INIT
for k in "$S1" "$S2"; do printf '{"key":"%s"}' "$k" | curl -s -X PUT --data @- "$KMS_URL/v1/sys/unseal" >/dev/null; done
for _ in $(seq 1 30); do [ "$(health)" = 200 ] && break; sleep 1; done
PW="pw-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s\n%s\n%s\n%s\n' "$S1" "$S2" "$PW" "$PW" | bash "$PROJECT/bootstrap.sh" >/dev/null 2>&1 || { bad "bootstrap failed"; exit 1; }
RPW="redis-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"; AKEY="sk-test-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
# mycache signs itself up (its own signup_with_kms.sh) — fake .env / agent.conf, temp credentials folder
export REG_ENV_FILE="$(mktemp)" REG_AGENT_CONF="$(mktemp)"
printf 'REDIS_VERSION=7-alpine\nREDIS_PASSWORD=%s\n' "$RPW" > "$REG_ENV_FILE"          # an old-style .env: the value is copied once
printf 'PORT=8892\nANTHROPIC_API_KEY=%s\n' "$AKEY" > "$REG_AGENT_CONF"
REG_SRV="$MYCACHE/connect_external/kms/signup_with_kms.sh"; REG_AGT="$MYCACHE/cache-agent/connect_external/kms/signup_with_kms.sh"
reg="$( { printf '%s\n' "$PW" | bash "$REG_SRV"; printf '%s\n' "$PW" | bash "$REG_AGT"; } 2>&1)"; rc=$?
reg2="$( { printf '%s\n' "$PW" | bash "$REG_SRV"; printf '%s\n' "$PW" | bash "$REG_AGT"; } 2>&1)"
rm -f "$REG_ENV_FILE" "$REG_AGENT_CONF"
if [ $rc = 0 ] && [ "$(echo "$reg" | grep -c 'copied into kms from')" = 2 ] && [ "$(echo "$reg2" | grep -c 'already in kms')" = 2 ] \
   && [ "$(echo "$reg2" | grep -c 'login kept')" = 2 ] && echo "$reg" | grep -q 'mycache-redis — may read: mycache/redis ·' \
   && echo "$reg" | grep -q 'mycache-cache-agent — may read: mycache/cache-agent mycache/redis shared/anthropic' \
   && [ "$(stat -c %a "$KMS_APPROLE_DIR/mycache-redis/secret_id")" = 600 ] && ! echo "$reg$reg2" | grep -qF -- "$RPW"; then
    ok "T0 server + agent each register themselves: own logins + files (600), secrets copied once, re-run no-op, nothing printed"
else bad "T0 register failed: $(echo "$reg" | grep -E 'ERROR|WARN' | head -2)"; fi

# helper: a Redis container from mycache's image, exactly like compose runs it
KADDR="http://$T:8200/v1/kv/data"                                       # the kms address as .env writes it
redis_run() {   # redis_run <REDIS_PASSWORD value> [more docker args…] — value passed by NAME
    REDIS_PASSWORD="$1" docker run -d --name "$R" --network "$NET" --tmpfs /run --tmpfs /mycache-secrets \
        -e REDIS_PASSWORD -e KMS_CREDENTIALS_DIR=/creds -v "$KMS_APPROLE_DIR/mycache-redis:/creds/mycache-redis:ro" \
        -v "$MYCACHE/connect_external/kms:/connect_external/kms:ro" "${@:2}" \
        --health-cmd "$HC" --health-interval 1s --health-retries 30 "$REDIS_IMAGE" \
        /opt/venv/bin/python /connect_external/kms/fetch_from_kms.py sh -c "$CMD" >/dev/null
}
agent_run() {   # agent_run <sh test> — the agent's own fetcher + login, values compared by NAME
    ANTHROPIC_API_KEY="$KADDR/shared/anthropic" REDIS_PASSWORD="$KADDR/mycache/redis" X1="$AKEY" X2="$RPW" \
    docker run --rm --network "$NET" -e ANTHROPIC_API_KEY -e REDIS_PASSWORD -e X1 -e X2 "${@:2}" \
        -e KMS_CREDENTIALS_DIR=/creds -v "$KMS_APPROLE_DIR/mycache-cache-agent:/creds/mycache-cache-agent:ro" \
        -v "$MYCACHE/cache-agent/connect_external/kms:/a:ro" "$REDIS_IMAGE" /opt/venv/bin/python /a/fetch_from_kms.py sh -c "$1" 2>&1
}
healthy() { for _ in $(seq 1 30); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$R" 2>/dev/null)" = healthy ] && return 0
            [ "$(docker inspect -f '{{.State.Running}}' "$R" 2>/dev/null)" = false ] && return 1; sleep 1; done; return 1; }
stopped() { for _ in $(seq 1 15); do [ "$(docker inspect -f '{{.State.Running}}' "$R" 2>/dev/null)" = false ] && return 0; sleep 1; done; return 1; }

# T1 + T7: the container fetches its own password (.env value = kms address)
redis_run "$KADDR/mycache/redis"
if healthy && docker logs "$R" 2>&1 | grep -q 'REDIS_PASSWORD ← kms (kv/data/mycache/redis)'; then
    ok "T1 the Redis container fetches REDIS_PASSWORD from kms itself (.env value = its kms address)"
    ok "T7 compose healthcheck (password from /run/redis.conf, no -a) → healthy"
else bad "T1/T7 container fetch: $(docker logs "$R" 2>&1 | tail -2)"; fi
# T9: the agent fetches its own secrets in the container (agent.conf values = kms addresses)
out="$(agent_run '[ "$ANTHROPIC_API_KEY" = "$X1" ] && [ "$REDIS_PASSWORD" = "$X2" ] && echo MATCH')"
echo "$out" | grep -q MATCH && echo "$out" | grep -q 'ANTHROPIC_API_KEY ← kms' && ! echo "$out" | grep -qF -- "$AKEY" \
    && ok "T9 cache-agent fetches ANTHROPIC_API_KEY + REDIS_PASSWORD itself (own fetcher + login), nothing printed" || bad "T9 '$(echo "$out" | tail -1)'"
# T4 + T6 on the same container
good="$(REDISCLI_AUTH="$RPW" docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
wrong="$(REDISCLI_AUTH=not-the-password docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
[ "$good" = PONG ] && echo "$wrong" | grep -qiE 'WRONGPASS|NOAUTH|invalid' \
    && ok "T4 Redis: the kms password works, a wrong one is refused" || bad "T4 good='$good' wrong='$wrong'"
leak6=0
docker inspect -f '{{json .Config.Cmd}} {{json .Args}} {{json .Config.Env}}' "$R" | grep -qF -- "$RPW" && leak6=1
ps -eo args | grep -v grep | grep -qF -- "$RPW" && leak6=1
docker exec "$R" sh -c 'cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\0" " "' | grep -qF -- "$RPW" && leak6=1
docker logs "$R" 2>&1 | grep -qF -- "$RPW" && leak6=1
[ "$(docker exec "$R" stat -c '%a %U' /run/redis.conf)" = "600 redis" ] || leak6=1
[ "$(docker exec "$R" stat -c '%a' /mycache-secrets/redis_password)" = 640 ] || leak6=1
[ $leak6 = 0 ] && ok "T6 password not in ps / docker inspect / args / container logs; /run/redis.conf 600, UI file 640 (RAM)" || bad "T6 password visible or file open"
docker rm -f "$R" >/dev/null

# T17: the Redis UI — password from the shared RAM volume, its real compose entrypoint
UIE="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis-commander:"):]
print(re.search(r"entrypoint:\n(?:\s+- .*\n)*?\s+- -c\n\s+- (.*)", r).group(1).replace("$$","$"))')"
docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=64k,mode=0750 "$VOL" >/dev/null
REDIS_PASSWORD="$KADDR/mycache/redis" docker run -d --name "$R" --network "$NET" --network-alias mycache-redis --tmpfs /run -v "$VOL:/mycache-secrets" \
    -e REDIS_PASSWORD -e KMS_CREDENTIALS_DIR=/creds -v "$KMS_APPROLE_DIR/mycache-redis:/creds/mycache-redis:ro" \
    -v "$MYCACHE/connect_external/kms:/connect_external/kms:ro" --health-cmd "$HC" --health-interval 1s --health-retries 30 \
    "$REDIS_IMAGE" /opt/venv/bin/python /connect_external/kms/fetch_from_kms.py sh -c "$CMD" >/dev/null
healthy
docker run -d --name "$U" --network "$NET" -v "$VOL:/mycache-secrets:ro" --entrypoint /usr/bin/dumb-init \
    rediscommander/redis-commander:latest -- sh -c "$UIE" >/dev/null
ui=""; for _ in $(seq 1 20); do ui="$(docker logs "$U" 2>&1)"; echo "$ui" | grep -qiE 'connected|listening' && break; sleep 1; done
sleep 2; ui="$(docker logs "$U" 2>&1)"
uiok=0; echo "$ui" | grep -qiE 'NOAUTH|WRONGPASS|invalid password|ECONNREFUSED' || uiok=1
info=""; for _ in $(seq 1 10); do info="$(docker exec "$U" wget -qO- http://127.0.0.1:8081/apiv2/server/info 2>/dev/null)"; echo "$info" | grep -q '"Redis version"' && break; sleep 1; done
echo "$info" | grep -q '"Redis version"' || uiok=0                                     # it really talks to Redis
docker inspect -f '{{json .Config.Cmd}} {{json .Args}} {{json .Config.Env}}' "$U" | grep -qF -- "$RPW" && uiok=0
echo "$ui" | grep -qF -- "$RPW" && uiok=0
[ "$(docker inspect -f '{{.State.Running}}' "$U")" = true ] || uiok=0
[ $uiok = 1 ] && ok "T17 Redis UI reads the password from the RAM volume and connects; not in its config / args / logs" \
    || bad "T17 Redis UI: $(echo "$ui" | grep -iE 'error|auth' | head -2) · Redis answered through the UI: $(echo "$info" | grep -c '"Redis version"')"
docker rm -f "$U" "$R" >/dev/null

# T3: each login is refused outside its own paths
redis_run "$KADDR/shared/anthropic"
stopped && docker logs "$R" 2>&1 | grep -q 'may not read' && r1=1 || r1=0
docker rm -f "$R" >/dev/null
e2="$(RABBITMQ_PASS="$KADDR/mychannels/rabbitmq" agent_run 'echo SHOULD-NOT-RUN' -e RABBITMQ_PASS)"
[ $r1 = 1 ] && echo "$e2" | grep -q 'may not read' && ! echo "$e2" | grep -q SHOULD-NOT-RUN \
    && ok "T3 each login is refused outside its own paths (container stops with the reason)" || bad "T3 access not limited ($r1)"

# T5: empty password → Redis refuses to start · T16: a plain value is used as written
redis_run ""
stopped && ok "T5 empty password → Redis refuses to start (fails closed)" || bad "T5 Redis runs without a password"
docker rm -f "$R" >/dev/null
redis_run "$RPW"
healthy && ! docker logs "$R" 2>&1 | grep -q '← kms' && ok "T16 a plain value (no kms address) is used as written — no kms call" || bad "T16 plain value"
docker rm -f "$R" >/dev/null

# T8 static: no script prints the password or passes it with -a
t8=0
grep -nE '(echo|printf).*\$\{?REDIS_PASSWORD' "$MYCACHE/start.sh" "$MYCACHE"/cache-agent/*.sh >/dev/null && t8=1
grep -nE -- '-a[", ]+.*REDIS_PASSWORD|"-a"' "$MYCACHE/docker-compose.yml" "$MYCACHE/cache-agent/server.py" "$MYCACHE"/*.sh "$MYCACHE"/cache-agent/*.sh >/dev/null && t8=1
for f in .env cache-agent/agent.conf; do                                         # tracked + secret-free
    git -C "$MYCACHE" ls-files --error-unmatch "$f" >/dev/null 2>&1 || t8=1
    grep -E '^[A-Z_]*(PASS|PASSWORD|SECRET|TOKEN|API_KEY)[A-Z_]*=.+' "$MYCACHE/$f" | grep -vqE '=https?://[^ ]+/v1/kv/' && t8=1   # only kms addresses
done
grep -rnE 'projectspace/kms|\.\./kms/|\.\./\.\./kms/' --include=*.sh --include=*.py --include=*.yml "$MYCACHE" | grep -v test_kms.sh >/dev/null && t8=1   # decoupled: HTTP only
for c in connect_external/kms/credentials cache-agent/connect_external/kms/credentials; do git -C "$MYCACHE" check-ignore -q "$c/x" || t8=1; done   # login files never in git
grep -rnE '\.\./connect_external' --include=*.sh --include=*.py "$MYCACHE/cache-agent" >/dev/null && t8=1   # the agent never uses the server's folder
[ $t8 = 0 ] && ok "T8 mycache never prints the password, never uses -a, uses no kms file (HTTP only), credentials/ git-ignored, agent uses only its own folder; examples clean" || bad "T8 a script prints / passes the password"

# T11 a new secret, the right way
NEW1="new-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"; NEW2="new-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
CE="$(mktemp)"; CA="$(mktemp)"; cp "$MYCACHE/.env" "$CE"; cp "$MYCACHE/cache-agent/agent.conf" "$CA"   # copies — never the real files
o1="$(printf 'TEST_NEW_KEY\n%s\n%s\n' "$PW" "$NEW1" | REG_ENV_FILE="$CE" bash "$MYCACHE/connect_external/kms/add_new_secret_to_kms.sh" 2>&1)"   # asks the name
o2="$(printf '%s\n%s\n' "$PW" "$NEW2" | REG_AGENT_CONF="$CA" bash "$MYCACHE/cache-agent/connect_external/kms/add_new_secret_to_kms.sh" TEST_AGENT_KEY 2>&1)"
lines=0; grep -qx 'TEST_NEW_KEY=http://kms-openbao:8200/v1/kv/data/mycache/redis' "$CE" && grep -qx 'TEST_AGENT_KEY=http://kms-openbao:8200/v1/kv/data/mycache/cache-agent' "$CA" \
    && [ "$(grep -c '^REDIS_PASSWORD=' "$CE")" = 1 ] && lines=1
o3="$(printf 'TEST_NEW_KEY\n%s\n%s\n' "$PW" "$NEW1" | REG_ENV_FILE="$CE" bash "$MYCACHE/connect_external/kms/add_new_secret_to_kms.sh" 2>&1)"
[ "$(grep -c '^TEST_NEW_KEY=' "$CE")" = 1 ] || lines=0                                         # same name again: updated, not duplicated
grep -qF -- "$NEW1" "$CE" "$CA" && lines=0; rm -f "$CE" "$CA"
# server: read back inside a container (values compared by NAME, never on a command line)
srv="$(TEST_NEW_KEY="$KADDR/mycache/redis" REDIS_PASSWORD="$KADDR/mycache/redis" X1="$NEW1" X2="$RPW" docker run --rm --network "$NET" \
        -e TEST_NEW_KEY -e REDIS_PASSWORD -e X1 -e X2 -e KMS_CREDENTIALS_DIR=/creds -v "$KMS_APPROLE_DIR/mycache-redis:/creds/mycache-redis:ro" \
        -v "$MYCACHE/connect_external/kms:/connect_external/kms:ro" "$REDIS_IMAGE" /opt/venv/bin/python /connect_external/kms/fetch_from_kms.py \
        sh -c '[ "$TEST_NEW_KEY" = "$X1" ] && [ "$REDIS_PASSWORD" = "$X2" ] && echo A' 2>/dev/null)"
out="$srv
$(TEST_AGENT_KEY="$KADDR/mycache/cache-agent" X3="$NEW2" agent_run '[ "$TEST_AGENT_KEY" = "$X3" ] && echo B' -e TEST_AGENT_KEY -e X3 | grep -x B)"
if [ "$out" = "$(printf 'A\nB')" ] && [ $lines = 1 ] && echo "$o1" | grep -q 'stored (version' && echo "$o2" | grep -q 'stored (version' \
   && ! echo "$o1$o2" | grep -qF -- "$NEW1" && ! echo "$o1$o2" | grep -qF -- "$NEW2"; then
    ok "T11 add_new_secret_to_kms.sh (server + agent): asks the name, stores in its own path, writes the config line (once), readable, nothing printed"
else bad "T11 add secret: lines=$lines · o1: $(echo "$o1" | tail -2 | tr "\n" " ") · o2: $(echo "$o2" | tail -1)"; fi

# T12 every script explains itself
bad12=""
for f in $(cd "$MYCACHE" && { git ls-files '*.sh'; ls connect_external/kms/*.sh cache-agent/connect_external/kms/*.sh; } | sort -u); do
    p="$MYCACHE/$f"; n="$(basename "$f")"
    [ "$(grep -c '^# ──────────' "$p")" -ge 2 ] && grep -q "^# $n — " "$p" || { bad12+=" $f(header)"; continue; }
    head -1 "$p" | grep -q '^#!' || continue                       # sourced library: header only
    case "$(head -1 "$p")" in '#!/bin/sh') sh_=sh ;; *) sh_=bash ;; esac
    out="$(cd /tmp && $sh_ "$p" --help 2>&1)"; rc=$?
    [ $rc = 0 ] && echo "$out" | head -1 | grep -q "$n" && echo "$out" | grep -q 'How' || bad12+=" $f(--help)"
done
for py in "$MYCACHE/connect_external/kms/fetch_from_kms.py" "$MYCACHE/cache-agent/connect_external/kms/fetch_from_kms.py"; do
    out="$(python3 "$py" --help 2>&1)"; echo "$out" | head -1 | grep -q fetch_from_kms.py && echo "$out" | grep -q How || bad12+=" ${py#$MYCACHE/}(--help)"; done
[ -z "$bad12" ] && ok "T12 every mycache script has a tidy header and answers --help" || bad "T12:$bad12"

# T13 the agent uses only its own login folder — the server's login is never mounted for it
t13=0; grep -q 'connect_external/kms/fetch_from_kms.py' "$MYCACHE/cache-agent/host_start.sh" || t13=1
grep -nE "\.\./connect_external|[ '=]/connect_external/kms" "$MYCACHE"/cache-agent/*.sh >/dev/null && t13=1   # the server's folder (../ or its in-container /connect_external/kms)
[ $t13 = 0 ] && ok "T13 the agent runs its own fetcher with its own login (never the server's)" || bad "T13 agent uses the server's folder"

# T14 first fetch with no credentials: in startup → message; by hand → signs up once by itself
if ls "$MYCACHE"/connect_external/kms/credentials/*/secret_id >/dev/null 2>&1; then o="SKIP"; else
    o="$( (cd /tmp && SVC_RUN=1 bash "$MYCACHE/start.sh" </dev/null; echo "rc=$?") 2>&1 )"; fi        # stops BEFORE docker compose
if ls "$MYCACHE"/cache-agent/connect_external/kms/credentials/*/secret_id >/dev/null 2>&1 || curl -fsS -o /dev/null --max-time 2 http://localhost:8892/health 2>/dev/null; then o2="SKIP"; else
    o2="$( (cd /tmp && SVC_RUN=1 bash "$MYCACHE/cache-agent/host_start.sh" </dev/null; echo "rc=$?") 2>&1 )"; fi
{ [ "$o" = SKIP ] || { echo "$o" | grep -q 'not signed up with kms yet' && echo "$o" | grep -q 'rc=1' && ! echo "$o" | grep -q 'Starting Redis'; }; } \
   && { [ "$o2" = SKIP ] || { echo "$o2" | grep -q 'not signed up with kms yet' && echo "$o2" | grep -q 'rc=1'; }; } \
    && ok "T14 no login, in startup: start.sh and cache-agent/host_start.sh → clear message, nothing started" || bad "T14: $(echo "$o$o2" | grep -iE 'error|info' | head -2)"

# T15 .env is the full list: every ${KEY} docker-compose.yml needs is a line in .env
miss=""
for k in $(grep -oE '\$\{[A-Z_]+' "$MYCACHE/docker-compose.yml" | tr -d '${' | sort -u); do grep -qE "^$k=" "$MYCACHE/.env" || miss+=" $k"; done
[ -z "$miss" ] && ok "T15 .env lists every key docker-compose.yml needs" || bad "T15 missing in .env:$miss"

# T2: seal the throwaway → the client refuses clearly
OWNER="$(printf '%s' "$PW" | python3 -c 'import sys,json; print(json.dumps({"password":sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$KMS_URL/v1/auth/userpass/login/nishan" | j 'd["auth"]["client_token"]')"
curl -s -o /dev/null -X PUT -H @<(printf 'X-Vault-Token: %s\n' "$OWNER") "$KMS_URL/v1/sys/seal"; unset OWNER
redis_run "$KADDR/mycache/redis"
stopped && docker logs "$R" 2>&1 | grep -q 'SEALED' \
    && ok "T2 kms sealed → the container stops with a clear 'SEALED' reason" || bad "T2 sealed case: $(docker logs "$R" 2>&1 | tail -1)"
docker rm -f "$R" >/dev/null

# T10
leak=0
for v in "$RPW" "$AKEY" "$PW" "$NEW1" "$NEW2"; do
    grep -rqF -- "$v" "$LOGS/kms" "$LOGS/mycache" "$AUDIT" 2>/dev/null && leak=1
    git -C "$PROJECT" grep -qF -- "$v" 2>/dev/null && leak=1
    git -C "$MYCACHE" grep -qF -- "$v" 2>/dev/null && leak=1
done
[ $leak = 0 ] && ok "T10 no test value in mirror logs, audit log or git" || bad "T10 a test value leaked"

unset S1 S2 PW RPW AKEY
[ "$FAIL" = 0 ] && ok "mycache tests passed (throwaway containers removed)" && exit 0
exit 1
