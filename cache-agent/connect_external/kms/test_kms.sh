#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_kms.sh — automatic tests: the cache-agent runs Redis and gets the secrets from kms
#
# What for    Prove the agent (the container's entry point) fetches its secrets from kms
#             with its own login, starts Redis with the password, keeps both alive,
#             prints nothing secret and keeps no secret in a file.
#
# Who         Claude (Auto test) — you can run it too; nothing live is touched.
#
# How         bash cache-agent/connect_external/kms/test_kms.sh        (≈3 min)
#
# Steps       a throwaway kms (127.0.0.1:8119, on a throwaway Docker network) + throwaway
#             mycache containers from mycache's own image, started exactly like compose
#             does (supervisor.py), with a COPY of cache-agent/ and a test agent.conf
#
# Checks      T0  the agent signs itself up (a kms address in agent.conf is never copied)
#             T1  supervisor: secrets from kms, Redis + API started · T7 healthcheck
#             T9  the API answers and sees Redis · T4 password works, wrong refused
#             T6  password nowhere visible · T17 Redis UI via the RAM volume (really answers)
#             T18 API dies → restarted by the supervisor · T19 Redis dies → container exits
#             T20 docker stop → clean exit 0 · T21 rotated password → next connection, no restart
#             T3  refused outside its own paths
#             T5  empty password → not started · T16 a plain value is used as written
#             T8  static: nothing printed, tracked .env / agent.conf secret-free, credentials
#                 ignored, one kms folder (the agent's) · T11 add_new_secret_to_kms.sh
#             T12 every script explains itself · T14 no login, in startup → message
#             T15 .env lists every key compose needs · T2 kms sealed → exits with SEALED
#             T10 no test value in logs / git
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

AGENT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"             # cache-agent (this file: connect_external/kms/)
MYCACHE="$(cd "$AGENT/.." && pwd)"
PROJECT="${KMS_PROJECT:-$_WS_ROOT/projectspace/kms}"                     # test-only: the kms image + bootstrap
DOCKERSPACE="$PROJECT/dockerspace"
LOGS="$_WS_ROOT/mountspace/logs/myworkspace/projectspace"
source "$DOCKERSPACE/.env"
T=kms-mycache-test; R=kms-mycache-redis-test; NET=kms-mycache-testnet; U=kms-mycache-ui-test; VOL=kms-mycache-test-secrets
export KMS_URL=http://127.0.0.1:8119
DATA="$(mktemp -d)"; AUDIT="$(mktemp -d)"; WORK="$(mktemp -d)"
export KMS_STATE_DIR="$(mktemp -d)" KMS_SECRETS_DIR="$(mktemp -d)/kms" KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32"
export KMS_APPROLE_DIR="$KMS_SECRETS_DIR/approle"   # where the agent's signup writes the login files (test only)
FAIL=0
ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
cleanup() { docker rm -f "$T" "$R" "$U" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1
            rm -rf "$DATA" "$AUDIT" "$WORK" "$KMS_STATE_DIR" "$(dirname "$KMS_SECRETS_DIR")"; }
trap cleanup EXIT
health() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$KMS_URL/v1/sys/health"; }
j() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
REDIS_IMAGE="mycache-redis:$(grep -E '^REDIS_VERSION=' "$MYCACHE/.env" | cut -d= -f2)"
docker image inspect "$REDIS_IMAGE" >/dev/null 2>&1 || (cd "$MYCACHE" && docker compose build -q redis) || { bad "mycache image $REDIS_IMAGE missing and could not be built"; exit 1; }
# the command, healthcheck and the UI's entrypoint exactly as docker compose runs them ($$ → $)
CFG="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null)"
CMD="$(echo "$CFG" | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(" ".join(re.findall(r"command:\n((?:\s+- .*\n)+)", r)[0].replace("$$","$").split("- ")).strip())')"
HC="$(echo "$CFG" | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(re.search(r"- CMD-SHELL\n\s+- (.*)", r).group(1).replace("$$","$"))')"
UIE="$(echo "$CFG" | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis-commander:"):]
print(re.search(r"entrypoint:\n(?:\s+- .*\n)*?\s+- -c\n\s+- (.*)", r).group(1).replace("$$","$"))')"
[ -n "$CMD" ] && [ -n "$HC" ] && [ -n "$UIE" ] || { bad "could not read the command / healthcheck / UI entrypoint from mycache's compose"; exit 1; }
echo "$CMD" | grep -q supervisor.py || { bad "compose command is not the supervisor: $CMD"; exit 1; }

# ── throwaway kms: init, unseal, bootstrap, seed the Redis password ───────────
docker rm -f "$T" "$R" "$U" >/dev/null 2>&1; docker volume rm "$VOL" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1
docker network create "$NET" >/dev/null || { bad "test network failed"; exit 1; }
docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=64k,mode=0750 "$VOL" >/dev/null
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
owner_token() { printf '%s' "$PW" | python3 -c 'import sys,json; print(json.dumps({"password":sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$KMS_URL/v1/auth/userpass/login/nishan" | j 'd["auth"]["client_token"]'; }
OT="$(owner_token)"     # the Redis password is mycache's own secret: the owner puts it into kms (here: seeded)
printf '%s' "$RPW" | python3 -c 'import sys,json; print(json.dumps({"data":{"REDIS_PASSWORD":sys.stdin.read()}}))' \
    | curl -s -o /dev/null -X POST -H @<(printf 'X-Vault-Token: %s\n' "$OT") --data @- "$KMS_URL/v1/kv/data/mycache/redis"; unset OT
KADDR="http://$T:8200/v1/kv/data"                                       # the kms address as agent.conf writes it

# ── T0: the agent signs itself up (fake agent.conf with a real key once, temp credentials) ──
export REG_AGENT_CONF="$(mktemp)"
printf 'PORT=8892\nANTHROPIC_API_KEY=%s\nREDIS_PASSWORD=%s/mycache/redis\n' "$AKEY" "$KADDR" > "$REG_AGENT_CONF"   # old-style key: copied once; an address: never
REG_AGT="$AGENT/connect_external/kms/signup_with_kms.sh"
reg="$(printf '%s\n' "$PW" | bash "$REG_AGT" 2>&1)"; rc=$?
reg2="$(printf '%s\n' "$PW" | bash "$REG_AGT" 2>&1)"
rm -f "$REG_AGENT_CONF"
if [ $rc = 0 ] && echo "$reg" | grep -q 'ANTHROPIC_API_KEY copied into kms from' && echo "$reg2" | grep -q 'ANTHROPIC_API_KEY already in kms' \
   && echo "$reg2" | grep -q 'login kept' && echo "$reg" | grep -q 'mycache-cache-agent — may read: mycache/cache-agent mycache/redis shared/anthropic' \
   && [ "$(stat -c %a "$KMS_APPROLE_DIR/mycache-cache-agent/secret_id")" = 600 ] && ! echo "$reg$reg2" | grep -qF -- "$AKEY" \
   && ! echo "$reg$reg2" | grep -q 'REDIS_PASSWORD copied'; then
    ok "T0 the agent signs itself up: own login + files (600), a real key copied once, a kms address never, re-run no-op, nothing printed"
else bad "T0 sign-up: $(echo "$reg" | grep -E 'ERROR|WARN' | head -2)"; fi

# ── helpers: a mycache container exactly like compose runs it (supervisor.py) ──
AD="$WORK/cache-agent"
run_mycache() {   # run_mycache <agent.conf text> [docker args…] — a COPY of cache-agent/ with the test login
    rm -rf "$AD"; mkdir -p "$AD"
    (cd "$AGENT" && tar --exclude=./connect_external/kms/credentials --exclude=./.venv --exclude=./memory --exclude='./__pycache__' -cf - .) | tar -xf - -C "$AD"
    printf '%s\n' "$1" > "$AD/agent.conf"
    mkdir -p "$AD/connect_external/kms/credentials" && cp -r "$KMS_APPROLE_DIR/mycache-cache-agent" "$AD/connect_external/kms/credentials/"
    chmod 700 "$AD/connect_external/kms/credentials" "$AD/connect_external/kms/credentials/mycache-cache-agent"
    docker run -d --name "$R" --network "$NET" --network-alias mycache-redis --tmpfs /run -v "$VOL:/mycache-secrets" \
        -v "$AD:/cache-agent" -e PYTHONDONTWRITEBYTECODE=1 "${@:2}" --health-cmd "$HC" --health-interval 1s --health-retries 30 "$REDIS_IMAGE" $CMD >/dev/null
}
CONF_OK="PORT=8892
ANTHROPIC_API_KEY=$KADDR/shared/anthropic
REDIS_PASSWORD=$KADDR/mycache/redis"
healthy() { for _ in $(seq 1 40); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$R" 2>/dev/null)" = healthy ] && return 0
            [ "$(docker inspect -f '{{.State.Running}}' "$R" 2>/dev/null)" = false ] && return 1; sleep 1; done; return 1; }
stopped() { for _ in $(seq 1 20); do [ "$(docker inspect -f '{{.State.Running}}' "$R" 2>/dev/null)" = false ] && return 0; sleep 1; done; return 1; }
api()     { for _ in $(seq 1 30); do docker exec "$R" wget -q -O - http://127.0.0.1:8892/health 2>/dev/null && return 0; sleep 1; done; return 1; }

# ── T1 + T7 + T9: the supervisor ─────────────────────────────────────────────
run_mycache "$CONF_OK"
lg="$(healthy; docker logs "$R" 2>&1)"
if healthy && echo "$lg" | grep -q 'REDIS_PASSWORD ← kms (mycache/redis)' && echo "$lg" | grep -q 'ANTHROPIC_API_KEY ← kms (shared/anthropic)' \
   && echo "$lg" | grep -q 'redis-server started' && echo "$lg" | grep -q 'API started on :8892'; then
    ok "T1 supervisor: both secrets from kms (own login), redis-server + API started"
    ok "T7 compose healthcheck (password from /run/redis.conf, no -a) → healthy"
else bad "T1/T7 supervisor: $(echo "$lg" | grep -E 'agent|ERROR' | tail -3)"; fi
h="$(api)"; echo "$h" | grep -q '"redis_running":true' && ok "T9 the agent API answers /health and sees Redis (redis-py, password asked from kms per connection)" || bad "T9 API: '$h'"

# ── T4 + T6 on the same container ────────────────────────────────────────────
good="$(REDISCLI_AUTH="$RPW" docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
wrong="$(REDISCLI_AUTH=not-the-password docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
[ "$good" = PONG ] && echo "$wrong" | grep -qiE 'WRONGPASS|NOAUTH|invalid' \
    && ok "T4 Redis: the kms password works, a wrong one is refused" || bad "T4 good='$good' wrong='$wrong'"
leak6=""
docker inspect -f '{{json .Config.Cmd}} {{json .Args}} {{json .Config.Env}}' "$R" | grep -qF -- "$RPW" && leak6+=" inspect"
ps -eo args | grep -v grep | grep -qF -- "$RPW" && leak6+=" host-ps"
docker exec "$R" sh -c 'cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\0" " "' | grep -qF -- "$RPW" && leak6+=" cmdline"
docker logs "$R" 2>&1 | grep -qF -- "$RPW" && leak6+=" logs-pw"
docker logs "$R" 2>&1 | grep -qF -- "$AKEY" && leak6+=" logs-key"
[ "$(docker exec "$R" stat -c '%a %U' /run/redis.conf)" = "600 redis" ] || leak6+=" redis.conf=$(docker exec "$R" stat -c '%a %U' /run/redis.conf 2>&1)"
[ "$(docker exec "$R" stat -c '%a' /mycache-secrets/redis_password)" = 640 ] || leak6+=" ui-file=$(docker exec "$R" ls -la /mycache-secrets/ 2>&1 | tail -1)"
[ -z "$leak6" ] && ok "T6 secrets not in ps / docker inspect / args / container logs; /run/redis.conf 600 redis, UI file 640 (RAM)" || bad "T6 a secret is visible or a file open:$leak6"

# ── T17: the Redis UI — password from the shared RAM volume, its real compose entrypoint ──
docker run -d --name "$U" --network "$NET" -v "$VOL:/mycache-secrets:ro" --entrypoint /usr/bin/dumb-init \
    rediscommander/redis-commander:latest -- sh -c "$UIE" >/dev/null
info=""; for _ in $(seq 1 20); do info="$(docker exec "$U" wget -qO- http://127.0.0.1:8081/apiv2/server/info 2>/dev/null)"; echo "$info" | grep -q '"Redis version"' && break; sleep 1; done
ui="$(docker logs "$U" 2>&1)"; uiok=1
echo "$info" | grep -q '"Redis version"' || uiok=0
echo "$ui" | grep -qiE 'NOAUTH|WRONGPASS|invalid password|ECONNREFUSED' && uiok=0
docker inspect -f '{{json .Config.Cmd}} {{json .Args}} {{json .Config.Env}}' "$U" | grep -qF -- "$RPW" && uiok=0
echo "$ui" | grep -qF -- "$RPW" && uiok=0
[ $uiok = 1 ] && ok "T17 Redis UI reads the password from the RAM volume and really talks to Redis; not in its config / args / logs" \
    || bad "T17 Redis UI: $(echo "$ui" | grep -iE 'error|auth' | head -2)"
docker rm -f "$U" >/dev/null

# ── T18: the API dies → the supervisor starts it again ───────────────────────
docker exec "$R" sh -c 'pkill -f "uvicorn server:app"' >/dev/null 2>&1
sleep 4; h="$(api)"
echo "$h" | grep -q '"status"' && docker logs "$R" 2>&1 | grep -q 'starting it again' \
    && ok "T18 the API died → the supervisor started it again (restart 1)" || bad "T18 API not restarted: $(docker logs "$R" 2>&1 | tail -2)"

# ── T19: Redis dies → the container exits (compose restarts it) ──────────────
REDISCLI_AUTH="$RPW" docker exec -e REDISCLI_AUTH "$R" redis-cli shutdown nosave >/dev/null 2>&1
stopped && docker logs "$R" 2>&1 | grep -q 'redis-server exited' && [ "$(docker inspect -f '{{.State.ExitCode}}' "$R")" != 0 ] \
    && ok "T19 Redis died → the supervisor exits non-zero (compose restarts the container)" || bad "T19: $(docker logs "$R" 2>&1 | tail -2)"
docker rm -f "$R" >/dev/null

# ── T20: docker stop → clean exit ────────────────────────────────────────────
run_mycache "$CONF_OK"; healthy
docker stop -t 30 "$R" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$R")" = 0 ] && docker logs "$R" 2>&1 | grep -q 'stopping — Redis saves and stops first' \
    && ok "T20 docker stop → Redis saved and stopped, then the API, exit 0" || bad "T20 exit $(docker inspect -f '{{.State.ExitCode}}' "$R")"
docker rm -f "$R" >/dev/null

# ── T3: the login is refused outside its own paths ───────────────────────────
run_mycache "PORT=8892
ANTHROPIC_API_KEY=$KADDR/shared/anthropic
REDIS_PASSWORD=$KADDR/mychannels/rabbitmq"
stopped && docker logs "$R" 2>&1 | grep -q 'may not read' && ok "T3 the agent's login is refused outside its own paths (container stops with the reason)" \
    || bad "T3 access not limited: $(docker logs "$R" 2>&1 | tail -1)"
docker rm -f "$R" >/dev/null

# ── T5: empty password → Redis is not started · T16: a plain value is used as written ──
run_mycache "PORT=8892
ANTHROPIC_API_KEY=$KADDR/shared/anthropic
REDIS_PASSWORD="
stopped && docker logs "$R" 2>&1 | grep -q 'REDIS_PASSWORD is empty' && ok "T5 empty password → Redis is not started (fails closed)" || bad "T5 Redis runs without a password"
docker rm -f "$R" >/dev/null
run_mycache "PORT=8892
ANTHROPIC_API_KEY=$KADDR/shared/anthropic
REDIS_PASSWORD=$RPW"
if healthy && ! docker logs "$R" 2>&1 | grep -q 'REDIS_PASSWORD ← kms' && [ "$(REDISCLI_AUTH="$RPW" docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)" = PONG ]; then
    ok "T16 a plain value (no kms address) is used as written — no kms call for it"
else bad "T16 plain value: running=$(docker inspect -f '{{.State.Running}}' "$R") · $(docker logs "$R" 2>&1 | grep -E 'agent|ERROR' | tail -2 | tr '\n' ' ')"; fi
docker rm -f "$R" >/dev/null

# ── T21: rotation — a new password in kms + Redis (ACL) is used by the agent's NEXT connection ──
run_mycache "$CONF_OK" -e KMS_CACHE_SECONDS=2; healthy; api >/dev/null
RPW2="redis-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
OT="$(owner_token)"; printf '%s' "$RPW2" | python3 -c 'import sys,json; print(json.dumps({"data":{"REDIS_PASSWORD":sys.stdin.read()}}))' \
    | curl -s -o /dev/null -X POST -H @<(printf 'X-Vault-Token: %s\n' "$OT") --data @- "$KMS_URL/v1/kv/data/mycache/redis"; unset OT
export RPW RPW2
docker exec -e RPW -e RPW2 "$R" sh -c 'REDISCLI_AUTH="$RPW" redis-cli ACL SETUSER default ">$RPW2" "<$RPW"' >/dev/null 2>&1   # new in, old out (by name, never argv on the host)
docker exec -e RPW2 "$R" sh -c 'REDISCLI_AUTH="$RPW2" redis-cli CLIENT KILL TYPE normal' >/dev/null 2>&1                     # drop every open connection → the agent must reconnect
sleep 3
h="$(docker exec "$R" wget -q -O - http://127.0.0.1:8892/health 2>/dev/null)"
c="$(docker exec "$R" wget -q -O - http://127.0.0.1:8892/api/redis/clients 2>/dev/null)"
old="$(docker exec -e RPW "$R" sh -c 'REDISCLI_AUTH="$RPW" redis-cli ping' 2>&1)"
echo "$h" | grep -q '"redis_running":true' && echo "$c" | grep -q '"count"' && echo "$old" | grep -qiE 'WRONGPASS|NOAUTH' \
    && ! docker logs "$R" 2>&1 | grep -q 'starting it again' \
    && ok "T21 rotation: new password in kms + Redis → the agent reconnected with it, no restart; the old one is refused" \
    || bad "T21 rotation: health='$h' old='$old' restarts=$(docker logs "$R" 2>&1 | grep -c 'starting it again')"
docker rm -f "$R" >/dev/null; unset RPW2

# ── T8 static ────────────────────────────────────────────────────────────────
t8=0
grep -nE '(echo|printf|print).*REDIS_PASSWORD' "$MYCACHE/start.sh" "$AGENT"/*.sh | grep -v 'in kms' >/dev/null && t8=1   # never printed
grep -nE -- '-a[", ]+.*REDIS_PASSWORD|"-a"' "$MYCACHE/docker-compose.yml" "$AGENT/server.py" "$MYCACHE"/*.sh "$AGENT"/*.sh >/dev/null && t8=1
for f in .env cache-agent/agent.conf; do                                         # tracked + secret-free (only kms addresses)
    git -C "$MYCACHE" ls-files --error-unmatch "$f" >/dev/null 2>&1 || t8=1
    grep -E '^[A-Z_]*(PASS|PASSWORD|SECRET|TOKEN|API_KEY)[A-Z_]*=.+' "$MYCACHE/$f" | grep -vqE '=https?://[^ ]+/v1/kv/' && t8=1
done
grep -rnE 'projectspace/kms|\.\./kms/|\.\./\.\./kms/' --include=*.sh --include=*.py --include=*.yml "$MYCACHE" | grep -v test_kms.sh >/dev/null && t8=1   # decoupled: HTTP only
git -C "$MYCACHE" check-ignore -q cache-agent/connect_external/kms/credentials/x || t8=1   # login files never in git
[ -d "$MYCACHE/connect_external" ] && t8=1                                                  # one kms folder: the agent's
grep -q '^REDIS_PASSWORD=' "$MYCACHE/.env" && t8=1                                           # .env: Redis settings only
[ $t8 = 0 ] && ok "T8 nothing printed, no -a, HTTP only, credentials ignored, .env + agent.conf tracked and secret-free, one kms folder (the agent's)" || bad "T8 static check failed"

# ── T11: a new secret, the right way — stored, line written, reaches the API's env ──
NEW2="new-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
CA="$(mktemp)"; printf '%s\n' "$CONF_OK" > "$CA"                                            # a copy — never the real agent.conf
o2="$(printf 'TEST_AGENT_KEY\n%s\n%s\n' "$PW" "$NEW2" | REG_AGENT_CONF="$CA" bash "$AGENT/connect_external/kms/add_new_secret_to_kms.sh" 2>&1)"   # asks the name
o3="$(printf '%s\n%s\n' "$PW" "$NEW2" | REG_AGENT_CONF="$CA" bash "$AGENT/connect_external/kms/add_new_secret_to_kms.sh" TEST_AGENT_KEY 2>&1)"
lines=0; grep -qx "TEST_AGENT_KEY=$KADDR/mycache/cache-agent" "$CA" && [ "$(grep -c '^TEST_AGENT_KEY=' "$CA")" = 1 ] && [ "$(grep -c '^REDIS_PASSWORD=' "$CA")" = 1 ] && lines=1
grep -qF -- "$NEW2" "$CA" && lines=0
run_mycache "$(cat "$CA")"; rm -f "$CA"; healthy
seen="$(docker exec "$R" sh -c 'for p in $(pgrep -f "uvicorn server:app"); do tr "\0" "\n" < /proc/$p/environ; done | grep -c "^TEST_AGENT_KEY=http://.*/v1/kv/data/mycache/cache-agent$"')"
leak11="$(docker exec "$R" sh -c 'cat /proc/[0-9]*/environ 2>/dev/null | tr "\0" "\n"' | grep -cF -- "$NEW2")"       # the VALUE is in no process env
docker rm -f "$R" >/dev/null
[ $lines = 1 ] && [ "${seen:-0}" -ge 1 ] && [ "${leak11:-1}" = 0 ] && echo "$o2" | grep -q 'stored (version' && ! echo "$o2$o3" | grep -qF -- "$NEW2" \
    && ok "T11 add_new_secret_to_kms.sh: asks the name, stores it, writes the agent.conf line once; the API gets the ADDRESS (never the value) by env; nothing printed" \
    || bad "T11 add secret: lines=$lines seen=${seen:-?} leak=${leak11:-?} · $(echo "$o2" | tail -1)"

# ── T12 every script explains itself ─────────────────────────────────────────
bad12=""
for f in $(cd "$MYCACHE" && { git ls-files '*.sh' '*.py'; ls cache-agent/connect_external/kms/*.sh; } | sort -u); do
    p="$MYCACHE/$f"; n="$(basename "$f")"
    case "$n" in server.py) continue ;; esac                           # FastAPI app: docstring, not a script
    [ "$(grep -c '^# ──────────' "$p")" -ge 2 ] && grep -q "^# $n — " "$p" || { bad12+=" $f(header)"; continue; }
    head -1 "$p" | grep -q '^#!' || continue                           # sourced library: header only
    case "$(head -1 "$p")" in '#!/bin/sh') run_=sh ;; *python*) run_=python3 ;; *) run_=bash ;; esac
    out="$(cd /tmp && $run_ "$p" --help 2>&1)"; rc=$?
    [ $rc = 0 ] && echo "$out" | head -1 | grep -q "$n" && echo "$out" | grep -q 'How' || bad12+=" $f(--help)"
done
[ -z "$bad12" ] && ok "T12 every mycache script has a tidy header and answers --help" || bad "T12:$bad12"

# ── T14 no login, in startup → clear message, nothing started ────────────────
if ls "$AGENT"/connect_external/kms/credentials/*/secret_id >/dev/null 2>&1; then o="SKIP"; else
    o="$( (cd /tmp && SVC_RUN=1 bash "$MYCACHE/start.sh" </dev/null; echo "rc=$?") 2>&1 )"; fi            # stops BEFORE docker compose
{ [ "$o" = SKIP ] || { echo "$o" | grep -q 'not signed up with kms yet' && echo "$o" | grep -q 'rc=1' && ! echo "$o" | grep -q 'Starting Redis'; }; } \
    && ok "T14 no login, in startup: start.sh → clear message, nothing started" || bad "T14: $(echo "$o" | grep -iE 'error|info' | head -2)"

# ── T15 .env is the full list: every ${KEY} docker-compose.yml needs is a line in .env ──
miss=""
for k in $(grep -oE '\$\{[A-Z_]+' "$MYCACHE/docker-compose.yml" | tr -d '${' | sort -u); do grep -qE "^$k=" "$MYCACHE/.env" || miss+=" $k"; done
[ -z "$miss" ] && ok "T15 .env lists every key docker-compose.yml needs" || bad "T15 missing in .env:$miss"

# ── T2: seal the throwaway → the container stops with SEALED ─────────────────
OT="$(owner_token)"; curl -s -o /dev/null -X PUT -H @<(printf 'X-Vault-Token: %s\n' "$OT") "$KMS_URL/v1/sys/seal"; unset OT
run_mycache "$CONF_OK"
stopped && docker logs "$R" 2>&1 | grep -q 'SEALED' \
    && ok "T2 kms sealed → the container stops with a clear 'SEALED' reason" || bad "T2 sealed case: $(docker logs "$R" 2>&1 | tail -1)"
docker rm -f "$R" >/dev/null

# ── T10 ──────────────────────────────────────────────────────────────────────
leak=0
for v in "$RPW" "$AKEY" "$PW" "$NEW2" "${RPW2:-}"; do [ -n "$v" ] || continue
    grep -rqF -- "$v" "$LOGS/kms" "$LOGS/mycache" "$AUDIT" 2>/dev/null && leak=1
    git -C "$PROJECT" grep -qF -- "$v" 2>/dev/null && leak=1
    git -C "$MYCACHE" grep -qF -- "$v" 2>/dev/null && leak=1
done
[ $leak = 0 ] && ok "T10 no test value in mirror logs, audit log or git" || bad "T10 a test value leaked"

unset S1 S2 PW RPW RPW2 AKEY NEW2
[ "$FAIL" = 0 ] && ok "mycache tests passed (throwaway containers removed)" && exit 0
exit 1
