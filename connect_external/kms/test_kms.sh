#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_kms.sh — automatic tests: mycache gets its secrets from kms
#
# What for    Prove the Redis server and the cache-agent fetch their secrets from kms,
#             print nothing, and keep no secret in a file.
#
# Who         Claude (Auto test) — you can run it too; nothing live is touched.
#
# How         bash connect_external/kms/test_kms.sh        (≈1 min)
#
# Steps       a throwaway kms (127.0.0.1:8119) + a throwaway Redis (no network) running
#             mycache's real docker-compose command and healthcheck
#
# Checks      T0  server + agent sign themselves up · T1 server fetch · T9 agent fetch
#             T3  refused outside own paths · T4 Redis password works, wrong refused
#             T5  empty password → Redis refuses to start · T6 password on no command line
#             T7  healthcheck without -a · T8 nothing printed, tracked .env / agent.conf
#                 secret-free, credentials ignored · T11 add_new_secret_to_kms.sh
#             T12 every script has a tidy header + --help · T13 two clients, own folders
#             T14 no credentials: by hand signs up once; in startup a message
#             T2  kms sealed → clear error · T10 no test value in logs / git
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
T=kms-mycache-test; R=kms-mycache-redis-test
export KMS_URL=http://127.0.0.1:8119
DATA="$(mktemp -d)"; AUDIT="$(mktemp -d)"
export KMS_STATE_DIR="$(mktemp -d)" KMS_SECRETS_DIR="$(mktemp -d)/kms" KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32"
export KMS_APPROLE_DIR="$KMS_SECRETS_DIR/approle"   # where mycache's client looks for its login files
FAIL=0
ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
cleanup() { docker rm -f "$T" "$R" >/dev/null 2>&1; rm -rf "$DATA" "$AUDIT" "$KMS_STATE_DIR" "$(dirname "$KMS_SECRETS_DIR")"; }
trap cleanup EXIT
health() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$KMS_URL/v1/sys/health"; }
j() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
REDIS_IMAGE="redis:$(grep -E '^REDIS_VERSION=' "$MYCACHE/.env" | cut -d= -f2)"
# the Redis command + healthcheck exactly as docker compose runs them ($$ → $)
CMD="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(re.search(r"command:\n\s+- sh\n\s+- -c\n\s+- (.*)", r).group(1).replace("$$","$"))')"
HC="$(cd "$MYCACHE" && docker compose config --no-interpolate 2>/dev/null | python3 -c '
import sys,re; t=sys.stdin.read(); r=t[t.index("\n  redis:"):t.index("\n  redis-commander:")]
print(re.search(r"- CMD-SHELL\n\s+- (.*)", r).group(1).replace("$$","$"))')"
[ -n "$CMD" ] && [ -n "$HC" ] || { bad "could not read the Redis command / healthcheck from mycache's compose"; exit 1; }

# ── throwaway kms: init, unseal, bootstrap, add mycache, seed values ──────────
docker rm -f "$T" "$R" >/dev/null 2>&1
docker run -d --name "$T" -p 127.0.0.1:8119:8200 --user "$(id -u):$(id -g)" -e SKIP_CHOWN=true \
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
printf 'REDIS_VERSION=7-alpine\nREDIS_PASSWORD=%s\n' "$RPW" > "$REG_ENV_FILE"; printf 'PORT=8892\nANTHROPIC_API_KEY=%s\n' "$AKEY" > "$REG_AGENT_CONF"
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

# T1
out="$( ( source "$MYCACHE/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-redis mycache/redis REDIS_PASSWORD && [ "$REDIS_PASSWORD" = "$RPW" ] && echo MATCH ) 2>&1 )"
[ "$out" = MATCH ] && ok "T1 mycache client (HTTP only) → REDIS_PASSWORD exported, nothing printed" || bad "T1 client: '$out'"
# T9
out="$( ( source "$MYCACHE/cache-agent/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-cache-agent shared/anthropic ANTHROPIC_API_KEY \
          && kms_get mycache-cache-agent mycache/redis REDIS_PASSWORD && [ "$ANTHROPIC_API_KEY" = "$AKEY" ] && [ "$REDIS_PASSWORD" = "$RPW" ] && echo MATCH ) 2>&1 )"
[ "$out" = MATCH ] && ok "T9 cache-agent (own client + login) gets ANTHROPIC_API_KEY and REDIS_PASSWORD" || bad "T9 '$out'"
# T3
e1="$( ( source "$MYCACHE/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-redis shared/anthropic ANTHROPIC_API_KEY ) 2>&1 )"; r1=$?
e2="$( ( source "$MYCACHE/cache-agent/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-cache-agent mychannels/rabbitmq RABBITMQ_PASS ) 2>&1 )"; r2=$?
[ $r1 = 1 ] && [ $r2 = 1 ] && echo "$e1$e2" | grep -q 'may not read' \
    && ok "T3 each AppRole is refused outside its own paths" || bad "T3 access not limited ($r1/$r2)"

# T4–T7: a throwaway Redis with mycache's real command (value passed by NAME: -e REDIS_PASSWORD)
export REDIS_PASSWORD="$RPW"
docker run -d --name "$R" --network none --tmpfs /run -e REDIS_PASSWORD \
    --health-cmd "$HC" --health-interval 1s --health-retries 30 "$REDIS_IMAGE" sh -c "$CMD" >/dev/null
for _ in $(seq 1 30); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$R" 2>/dev/null)" = healthy ] && break; sleep 1; done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$R")" = healthy ] && ok "T7 compose healthcheck (REDISCLI_AUTH, no -a) → healthy" || bad "T7 healthcheck not healthy"
good="$(REDISCLI_AUTH="$RPW" docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
wrong="$(REDISCLI_AUTH=not-the-password docker exec -e REDISCLI_AUTH "$R" redis-cli ping 2>&1)"
[ "$good" = PONG ] && echo "$wrong" | grep -qiE 'WRONGPASS|NOAUTH|invalid' \
    && ok "T4 Redis: the kms password works, a wrong one is refused" || bad "T4 good='$good' wrong='$wrong'"
leak6=0
docker inspect -f '{{json .Config.Cmd}} {{json .Args}}' "$R" | grep -qF -- "$RPW" && leak6=1
ps -eo args | grep -v grep | grep -qF -- "$RPW" && leak6=1
docker exec "$R" sh -c 'cat /proc/[0-9]*/cmdline 2>/dev/null | tr "\0" " "' | grep -qF -- "$RPW" && leak6=1
[ "$(docker exec "$R" stat -c '%a %U' /run/redis.conf)" = "600 redis" ] || leak6=1
[ $leak6 = 0 ] && ok "T6 password not in ps / docker inspect / process args; /run/redis.conf 600 redis (RAM)" || bad "T6 password visible or config file open"
docker rm -f "$R" >/dev/null
REDIS_PASSWORD="" docker run -d --name "$R" --network none --tmpfs /run -e REDIS_PASSWORD "$REDIS_IMAGE" sh -c "$CMD" >/dev/null
sleep 3
[ "$(docker inspect -f '{{.State.Running}}' "$R" 2>/dev/null)" = false ] && ok "T5 empty password → Redis refuses to start (fails closed)" || bad "T5 Redis runs without a password"
docker rm -f "$R" >/dev/null; unset REDIS_PASSWORD

# T8 static: no script prints the password or passes it with -a
t8=0
grep -nE '(echo|printf).*\$\{?REDIS_PASSWORD' "$MYCACHE/start.sh" "$MYCACHE"/cache-agent/*.sh >/dev/null && t8=1
grep -nE -- '-a[", ]+.*REDIS_PASSWORD|"-a"' "$MYCACHE/docker-compose.yml" "$MYCACHE/cache-agent/server.py" "$MYCACHE"/*.sh "$MYCACHE"/cache-agent/*.sh >/dev/null && t8=1
for f in .env cache-agent/agent.conf; do                                         # tracked + secret-free
    git -C "$MYCACHE" ls-files --error-unmatch "$f" >/dev/null 2>&1 || t8=1
    grep -qE '^[A-Z_]*(PASS|PASSWORD|SECRET|TOKEN|API_KEY)[A-Z_]*=.+' "$MYCACHE/$f" && t8=1
done
grep -rnE 'projectspace/kms|\.\./kms/|\.\./\.\./kms/' --include=*.sh --include=*.py --include=*.yml "$MYCACHE" | grep -v test_kms.sh >/dev/null && t8=1   # decoupled: HTTP only
for c in connect_external/kms/credentials cache-agent/connect_external/kms/credentials; do git -C "$MYCACHE" check-ignore -q "$c/x" || t8=1; done   # login files never in git
grep -rnE '\.\./connect_external' --include=*.sh --include=*.py "$MYCACHE/cache-agent" >/dev/null && t8=1   # the agent never uses the server's folder
[ $t8 = 0 ] && ok "T8 mycache never prints the password, never uses -a, uses no kms file (HTTP only), credentials/ git-ignored, agent uses only its own folder; examples clean" || bad "T8 a script prints / passes the password"

# T11 a new secret, the right way
NEW1="new-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"; NEW2="new-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
o1="$(printf '%s\n%s\n' "$PW" "$NEW1" | bash "$MYCACHE/connect_external/kms/add_new_secret_to_kms.sh" TEST_NEW_KEY 2>&1)"
o2="$(printf '%s\n%s\n' "$PW" "$NEW2" | bash "$MYCACHE/cache-agent/connect_external/kms/add_new_secret_to_kms.sh" TEST_AGENT_KEY 2>&1)"
out="$( ( source "$MYCACHE/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-redis mycache/redis TEST_NEW_KEY REDIS_PASSWORD \
          && [ "$TEST_NEW_KEY" = "$NEW1" ] && [ "$REDIS_PASSWORD" = "$RPW" ] && echo A
          source "$MYCACHE/cache-agent/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-cache-agent mycache/cache-agent TEST_AGENT_KEY \
          && [ "$TEST_AGENT_KEY" = "$NEW2" ] && echo B ) 2>&1 )"
if [ "$out" = "$(printf 'A\nB')" ] && echo "$o1" | grep -q 'stored (version' && echo "$o2" | grep -q 'stored (version' \
   && ! echo "$o1$o2" | grep -qF -- "$NEW1" && ! echo "$o1$o2" | grep -qF -- "$NEW2"; then
    ok "T11 add_new_secret_to_kms.sh (server + agent): stored in own path, readable, old keys kept, nothing printed"
else bad "T11 add secret: '$out' / $(echo "$o1$o2" | grep -i error | head -1)"; fi

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
[ -z "$bad12" ] && ok "T12 every mycache script has a tidy header and answers --help" || bad "T12:$bad12"

# T13 both clients in ONE shell, using their default folders (regression: kms_get must not change a global)
t13="$( ( unset KMS_APPROLE_DIR
          d1="$MYCACHE/connect_external/kms/credentials"; d2="$MYCACHE/cache-agent/connect_external/kms/credentials"
          ls -d "$d1/mycache-redis" "$d2/mycache-cache-agent" >/dev/null 2>&1 || { echo "SKIP no live login files"; exit 0; }
          source "$MYCACHE/connect_external/kms/fetch_from_kms.sh"; KMS_URL=http://127.0.0.1:8110 kms_get mycache-redis mycache/redis REDIS_PASSWORD >/dev/null 2>&1; r1=$?
          source "$MYCACHE/cache-agent/connect_external/kms/fetch_from_kms.sh"; KMS_URL=http://127.0.0.1:8110 kms_get mycache-cache-agent mycache/redis REDIS_PASSWORD 2>&1 | grep -q 'no kms login files' && echo WRONG-FOLDER
          [ -z "${KMS_APPROLE_DIR:-}" ] && echo "global untouched" || echo "global CHANGED" ) )"
case "$t13" in *SKIP*) ok "T13 skipped (no live login files)";; *WRONG-FOLDER*|*CHANGED*) bad "T13 kms_get leaks its folder into a global: $t13";; *) ok "T13 both clients in one shell use their own folders; global untouched";; esac

# T14 first fetch with no credentials: in startup → message; by hand → signs up once by itself
rm -rf "$KMS_APPROLE_DIR/mycache-redis"
o="$( ( SVC_RUN=1 bash -c "source '$MYCACHE/connect_external/kms/fetch_from_kms.sh'; kms_get mycache-redis mycache/redis REDIS_PASSWORD; echo rc=\$?" ) 2>&1 )"
o2="$( ( printf '%s\n' "$PW" | KMS_AUTO_REGISTER=1 REG_ENV_FILE=/dev/null bash -c "source '$MYCACHE/connect_external/kms/fetch_from_kms.sh'; kms_get mycache-redis mycache/redis REDIS_PASSWORD && [ \"\$REDIS_PASSWORD\" = '$RPW' ] && echo MATCH" ) 2>&1 )"
echo "$o" | grep -q 'not signed up' && echo "$o" | grep -q 'rc=1' && echo "$o2" | grep -q MATCH && [ -s "$KMS_APPROLE_DIR/mycache-redis/secret_id" ] \
    && ok "T14 no credentials: in startup → clear message · by hand → signs up once by itself, then fetches" || bad "T14 self sign-up: $(echo "$o$o2" | grep -iE 'error|info' | head -2)"

# T2: seal the throwaway → the client refuses clearly
OWNER="$(printf '%s' "$PW" | python3 -c 'import sys,json; print(json.dumps({"password":sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$KMS_URL/v1/auth/userpass/login/nishan" | j 'd["auth"]["client_token"]')"
curl -s -o /dev/null -X PUT -H @<(printf 'X-Vault-Token: %s\n' "$OWNER") "$KMS_URL/v1/sys/seal"; unset OWNER
out="$( ( unset REDIS_PASSWORD; source "$MYCACHE/connect_external/kms/fetch_from_kms.sh"; kms_get mycache-redis mycache/redis REDIS_PASSWORD; echo "rc=$? set=${REDIS_PASSWORD:+yes}" ) 2>&1 )"
echo "$out" | grep -q 'SEALED' && echo "$out" | grep -q 'rc=1 set=$' \
    && ok "T2 kms sealed → clear 'SEALED' error, nothing exported" || bad "T2 sealed case: $out"

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
