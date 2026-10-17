#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_agent_signup.sh — the cache-agent signs ITSELF up with kms (TESTSERVER-24), on a THROWAWAY kms + a temp copy
#
# What for    Prove supervisor.py's first step: no kms login + kms's master_password mounted READ-ONLY → it logs in
#             to kms itself and signs up with its own signup_with_kms.sh (bash + curl in mycache's image); the new
#             login works; an empty / missing password stops with one clear line; the host start.sh checks it before
#             the start. The live kms, the live image tag, its usb/ folder and the real credentials/ are never touched
#             (checked before/after).
# Checks      A1 no login + master_password mounted read-only → signed up: credentials/<login>/ (600, owner = folder)
#             A2 the mounted password file is untouched (read-only mount: the agent cannot change it)
#             A3 the new login reads its own kms entry (AppRole login works)
#             A4 a second start → already signed up → nothing done
#             A5 no login + master_password empty → exit 1 with one clear line naming the file
#             A6 host start.sh: no login + master_password filled → the container start follows (stubbed) · empty,
#                inside startup → one clear line, no start (no restart loop)
#             A7 no token or password value in any output
# How         bash cache-agent/connect_external/kms/test_agent_signup.sh      (Docker + the kms image; builds a
#             test image mycache-redis:agent-signup-test from this checkout, removed at the end; ~1 min)
#             from a test copy: KMS_PROJECT=~/myworkspace/projectspace/kms bash …
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; AGENT="$(cd "$HERE/../.." && pwd)"; PROJ="$(dirname "$AGENT")"
KMSP="${KMS_PROJECT:-$_WS_ROOT/projectspace/kms}"            # test-only: the kms image + bootstrap (like test_kms.sh)
[ -f "$KMSP/dockerspace/.env" ] || { echo "kms not found at $KMSP — set KMS_PROJECT=<the kms project>"; exit 1; }
RWS="$(cd "$KMSP/../.." && pwd)"
OPENBAO_IMAGE="$(grep -E '^OPENBAO_IMAGE=' "$KMSP/dockerspace/.env" | cut -d= -f2-)"   # only the image — never kms's folders
T=kms-cachesignup-test; P=8122; U=http://127.0.0.1:$P; IMG=mycache-redis:agent-signup-test
TMP="$(mktemp -d)"; FAIL=0; OUT="$TMP/all_output"
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
fail() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
cleanup() { docker rm -f "$T" >/dev/null 2>&1; docker image rm "$IMG" >/dev/null 2>&1
            rm -rf "$TMP" 2>/dev/null || docker run --rm -v "$TMP:/t" alpine:3 rm -rf /t/proj >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
j() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
# the real things this test must NOT touch
REAL_STATE="$(stat -c '%n %s %Y' "$RWS/projectspace/mycache/cache-agent/connect_external/kms/credentials"/*/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/*/* 2>/dev/null | sort)"
LIVE_IMG="$(docker image inspect -f '{{.Id}}' "mycache-redis:$(grep -E '^REDIS_VERSION=' "$PROJ/.env" | cut -d= -f2)" 2>/dev/null)"

# ── mycache's image from THIS checkout (bash + curl), under a test-only tag ──────
REDIS_VERSION="$(grep -E '^REDIS_VERSION=' "$PROJ/.env" | cut -d= -f2)"; REDIS_DIGEST="$(grep -E '^REDIS_DIGEST=' "$PROJ/.env" | cut -d= -f2)"
docker build -q -t "$IMG" -f "$PROJ/dockerspace/Dockerfile" --build-arg REDIS_VERSION="$REDIS_VERSION" \
    ${REDIS_DIGEST:+--build-arg REDIS_DIGEST="$REDIS_DIGEST"} "$PROJ" >/dev/null || { fail "test image did not build"; exit 1; }
docker run --rm --entrypoint sh "$IMG" -c 'command -v bash && command -v curl' >/dev/null \
    && ok "A0 mycache's image has bash + curl (its own signup_with_kms.sh can run inside)" || fail "A0 bash / curl missing in the image"

# ── a throwaway kms with its foundation (owner login) — kms's usb/ = temp folders ─
mkdir -p "$TMP/kms/data" "$TMP/kms/audit" "$TMP/usb" "$TMP/state"
docker rm -f "$T" >/dev/null 2>&1
docker run -d --name "$T" -p "127.0.0.1:$P:8200" --user "$(id -u):$(id -g)" -e SKIP_CHOWN=true \
    -v "$KMSP/dockerspace/config:/openbao/config:ro" -v "$TMP/kms/data:/openbao/data" -v "$TMP/kms/audit:/openbao/audit" \
    "$OPENBAO_IMAGE" server >/dev/null || { fail "throwaway kms did not start"; exit 1; }
for _ in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$U/v1/sys/health")" = 501 ] && break; sleep 1; done
INIT="$(curl -s -X PUT -d '{"secret_shares":3,"secret_threshold":2}' "$U/v1/sys/init")"
S1="$(j 'd["keys_base64"][0]' <<< "$INIT")"; S2="$(j 'd["keys_base64"][1]' <<< "$INIT")"; R0="$(j 'd["root_token"]' <<< "$INIT")"; unset INIT
for k in "$S1" "$S2"; do curl -s -o /dev/null -X PUT -d "{\"key\":\"$k\"}" "$U/v1/sys/unseal"; done
for _ in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$U/v1/sys/health")" = 200 ] && break; sleep 1; done
curl -s -o /dev/null -X POST -H "X-Vault-Token: $R0" "$U/v1/auth/token/revoke-self"; unset R0
PW="pw-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export KMS_URL="$U" KMS_STATE_DIR="$TMP/state" KMS_STATIC_KEY_DIR="$TMP/usb" KMS_USB_BACKUP_DIR="$TMP/usbbk" KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32"
printf '%s\n%s\n%s\n%s\n' "$S1" "$S2" "$PW" "$PW" | bash "$KMSP/bootstrap.sh" >/dev/null 2>&1 || { fail "bootstrap of the throwaway kms failed"; exit 1; }
TOK="$(printf '%s' "$PW" | python3 -c 'import sys,json; print(json.dumps({"password":sys.stdin.read()}))' | curl -s -X POST --data @- "$U/v1/auth/userpass/login/nishan" | j 'd["auth"]["client_token"]')"
[ -n "$TOK" ] || { fail "no owner login on the throwaway kms"; exit 1; }
printf '%s' "rpw-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')" | python3 -c 'import sys,json; print(json.dumps({"data":{"REDIS_PASSWORD":sys.stdin.read()}}))' \
    | curl -s -o /dev/null -X POST -H @<(printf 'X-Vault-Token: %s\n' "$TOK") --data @- "$U/v1/kv/data/mycache/redis"   # mycache's own entry (owner seeds it)

# ── a temp copy of the project: cache-agent with NO login, agent.conf pointing at the throwaway kms ──────────
C="$TMP/proj"; mkdir -p "$C/cache-agent/connect_external/kms"; cp -a "$PROJ/start.sh" "$C/"
cp -a "$AGENT/supervisor.py" "$C/cache-agent/"; cp -a "$HERE/kms.py" "$HERE/signup_with_kms.sh" "$C/cache-agent/connect_external/kms/"
sed "s#http://kms-openbao:8200#$U#g" "$AGENT/agent.conf" > "$C/cache-agent/agent.conf"
CRED="$C/cache-agent/connect_external/kms/credentials"
MPW="$TMP/usb/kms/master_password"; mkdir -p "$MPW"; printf '%s\n' "$PW" > "$MPW/master_password"; chmod 600 "$MPW/master_password"
ensure() {  # supervisor.py's ensure_login on the copy — in a THROWAWAY container of the test image, as root like
            # compose runs it; only the copy + the TEMP master_password folder (read-only) mounted; never the live container
    docker run --rm --network host -e KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32" \
        -e KMS_MASTER_PASSWORD_FILE=/mpw/master_password -v "$MPW:/mpw:ro" \
        -v "$C:/proj" -w /proj/cache-agent --entrypoint /opt/venv/bin/python "$IMG" -c '
import supervisor
supervisor.ensure_login(supervisor.settings())
print("ENSURE_DONE")' 2>&1 | tee -a "$OUT"; }

# A1 + A2 + A3
sum0="$(stat -c '%s %Y' "$MPW/master_password")"
o="$(ensure)"
L="$(ls -d "$CRED"/*/ 2>/dev/null | head -1)"
[ -n "$L" ] && [ -s "$L/role_id" ] && [ -s "$L/secret_id" ] && [ "$(stat -c %a "$L/secret_id")" = 600 ] \
    && [ "$(stat -c %u "$L/secret_id")" = "$(stat -c %u "$C/cache-agent")" ] && grep -q ENSURE_DONE <<< "$o" \
    && ok "A1 no login + master_password mounted read-only → signed up with its own signup_with_kms.sh: $(basename "$L") (600, owner = the folder's)" || fail "A1 [$(tail -5 <<< "$o")]"
[ "$(stat -c '%s %Y' "$MPW/master_password")" = "$sum0" ] && [ "$(cat "$MPW/master_password")" = "$PW" ] \
    && ok "A2 the mounted password file is untouched (read-only)" || fail "A2 master_password changed"
AT="$(python3 -c 'import sys,json; print(json.dumps({"role_id":open(sys.argv[1]).read().strip(),"secret_id":open(sys.argv[2]).read().strip()}))' "$L/role_id" "$L/secret_id" 2>/dev/null \
     | curl -s -X POST --data @- "$U/v1/auth/approle/login" | j 'd["auth"]["client_token"]')"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "X-Vault-Token: ${AT:-x}" "$U/v1/kv/data/mycache/redis")"
[ -n "$AT" ] && [ "$code" = 200 ] && ok "A3 the new login works: it reads its own kms entry (mycache/redis)" || fail "A3 approle=${AT:+yes} read=$code"

# A4 a second start
o="$(ensure)"; grep -q ENSURE_DONE <<< "$o" && ! grep -q 'signing up' <<< "$o" && ok "A4 already signed up → nothing done" || fail "A4 [$o]"

# A5 no login + the password file empty
rm -rf "$CRED"; : > "$MPW/master_password"; o="$(ensure)"
! grep -q ENSURE_DONE <<< "$o" && grep -q "kms's master_password is empty — put your kms password into" <<< "$o" && [ ! -d "$CRED" -o -z "$(ls -A "$CRED" 2>/dev/null)" ] \
    && ok "A5 no login + master_password empty → stops with one clear line naming the file, nothing signed up" || fail "A5 [$o]"

# A6 host start.sh: the hand-over (docker is stubbed on PATH: prints STUB_CONTAINER_START and stops there)
mkdir -p "$TMP/bin"; printf '#!/bin/bash\necho STUB_CONTAINER_START\nexit 1\n' > "$TMP/bin/docker"; chmod +x "$TMP/bin/docker"
printf 'REDIS_VERSION=%s\nKMS_MASTER_PASSWORD_DIR=%s\n' "$REDIS_VERSION" "$MPW" > "$C/.env"
printf '%s\n' "$PW" > "$MPW/master_password"
o="$(cd "$C" && PATH="$TMP/bin:$PATH" SVC_RUN=1 bash start.sh </dev/null 2>&1)"
: > "$MPW/master_password"
o2="$(cd "$C" && PATH="$TMP/bin:$PATH" SVC_RUN=1 bash start.sh </dev/null 2>&1)"; rc2=$?
grep -q STUB_CONTAINER_START <<< "$o" && grep -q 'signs itself up as it starts' <<< "$o" \
  && [ $rc2 = 1 ] && grep -q "put your kms password into $MPW/master_password" <<< "$o2" && ! grep -q STUB_CONTAINER_START <<< "$o2" \
    && ok "A6 host start.sh: no login + master_password filled → the container starts (the agent signs up) · empty, inside startup → one clear line, no start" \
    || fail "A6 [$(tail -2 <<< "$o")] [$(tail -1 <<< "$o2")]"

# A7 no secrets in the output
{ grep -qF -- "$TOK" "$OUT" || grep -qF -- "$PW" "$OUT"; } && fail "A7 a token / password appeared in the output" || ok "A7 no token or password in any output"
unset TOK PW S1 S2 AT

[ "$(stat -c '%n %s %Y' "$RWS/projectspace/mycache/cache-agent/connect_external/kms/credentials"/*/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/*/* 2>/dev/null | sort)" = "$REAL_STATE" ] \
  && [ "$(docker image inspect -f '{{.Id}}' "mycache-redis:$REDIS_VERSION" 2>/dev/null)" = "$LIVE_IMG" ] \
    && ok "the real credentials/, usb/ and the live image are untouched" || fail "a REAL file or the live image changed — check credentials/, mountspace/usb/, docker images"
[ $FAIL = 0 ] && ok "agent sign-up tests passed (throwaway kms + test image removed)" || { echo "  some checks failed"; exit 1; }
