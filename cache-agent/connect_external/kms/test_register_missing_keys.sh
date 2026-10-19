#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_register_missing_keys.sh — a key kms does not have → the cache-agent registers it with an initial random value
#                                  (owner rule 2026-10-17), on a THROWAWAY kms + a temp copy
#
# What for    Prove supervisor.py's fetch on a fresh kms: a missing key is created by its own
#             register_kms_cache_keys_with_random_initial.sh (owner login from the read-only master_password),
#             then fetched — Redis is never stopped by a missing key; nothing is ever overwritten; no value shown.
#             The live kms, its usb/ folder and the real credentials/ are never touched (checked before/after).
# Checks      R1 a fresh kms: every key is missing → registered in one go, every key fetched, "⚠ placeholder" named;
#                sign-up itself no longer says "set / add it by hand" for them
#             R2 in kms: ANTHROPIC_API_KEY = placeholder-<32>; note initial_ANTHROPIC_API_KEY = placeholder;v1;<by>;<today>
#             R3 an own password missing (entry gone) → a RANDOM value (32 letters/digits), note "random", other entries kept
#             R4 a second fetch → nothing registered
#             R5 by hand, the key already in kms with YOUR value → "already in kms", value + version unchanged
#             R6 a key missing + master_password empty → one line naming the file and the by-hand command, exit 1, nothing written
#             R7 no value, token or password in any output
#             R8 no names (the all-keys mode, for svcmgt/register_all_kms_keys.sh): every kms line of agent.conf — the
#                missing one created, the rest "already in kms"
#             R9 kms's base is ONE line (KMS_URL): the copy changed only that line, every ${KMS_URL}/… key followed it
# How         bash cache-agent/connect_external/kms/test_register_missing_keys.sh      (Docker + the kms image; builds a
#             test image mycache-redis:register-test from this checkout, removed at the end; ~1 min) — from a test copy: KMS_PROJECT=~/myworkspace/projectspace/kms bash …
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; AGENT="$(cd "$HERE/../.." && pwd)"; PROJ="$(dirname "$AGENT")"
KMSP="${KMS_PROJECT:-$_WS_ROOT/projectspace/kms}"
[ -f "$KMSP/dockerspace/.env" ] || { echo "kms not found at $KMSP — set KMS_PROJECT=<the kms project>"; exit 1; }
RWS="$(cd "$KMSP/../.." && pwd)"
OPENBAO_IMAGE="$(grep -E '^OPENBAO_IMAGE=' "$KMSP/dockerspace/.env" | cut -d= -f2-)"   # only the image — never kms's folders
T=kms-regkeys-mycache-test; P=8130; U=http://127.0.0.1:$P; TODAY="$(date +%Y-%m-%d)"
TMP="$(mktemp -d)"; FAIL=0; OUT="$TMP/all_output"
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
fail() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
cleanup() { docker rm -f "$T" >/dev/null 2>&1; docker image rm "$IMG" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
j() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
REAL_STATE="$(stat -c '%n %s %Y' "$RWS/projectspace/mycache/cache-agent/connect_external/kms/credentials"/*/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/*/* 2>/dev/null | sort)"

# ── a throwaway kms with its foundation — kms's usb/ = temp folders ──────────────
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
kget()  { curl -s -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/data/$1" | j "d['data']['data'].get('$2','')"; }
kver()  { curl -s -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/metadata/$1" | j "d['data']['current_version']"; }
knote() { curl -s -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/metadata/$1" | j "(d['data'].get('custom_metadata') or {}).get('initial_$2','')"; }

# ── a temp copy: cache-agent signed up (as on your VM), agent.conf pointing at the throwaway kms ─────────────────────
C="$TMP/proj"; KD="$C/cache-agent/connect_external/kms"; mkdir -p "$KD"
cp -a "$AGENT/supervisor.py" "$C/cache-agent/"; cp -a "$HERE/kms.py" "$HERE/kms_conf.sh" "$HERE/signup_with_kms.sh" "$HERE/register_kms_cache_keys_with_random_initial.sh" "$KD/"
sed "s#^KMS_URL=.*#KMS_URL=$U#" "$AGENT/agent.conf" > "$C/cache-agent/agent.conf"   # kms's base: ONE line (TESTSERVER-46)
IMG=mycache-redis:register-test                          # this checkout's image (bash + curl), a test-only tag — never the live one
REDIS_VERSION="$(grep -E '^REDIS_VERSION=' "$PROJ/.env" | cut -d= -f2)"; _DIG="$(grep -E '^REDIS_DIGEST=' "$PROJ/.env" | cut -d= -f2)"
docker build -q -t "$IMG" -f "$PROJ/dockerspace/Dockerfile" --build-arg REDIS_VERSION="$REDIS_VERSION" ${_DIG:+--build-arg REDIS_DIGEST="$_DIG"} "$PROJ" >/dev/null \
    || { fail "test image did not build"; exit 1; }
MPW="$TMP/usb/kms/master_password"; mkdir -p "$MPW"; printf '%s\n' "$PW" > "$MPW/master_password"; chmod 600 "$MPW/master_password"
agent() {  # supervisor.py's sign-up + fetch on the copy — a THROWAWAY container of the test image, the TEMP
           # master_password folder read-only; never the live container
    docker run --rm --network host --user "$(id -u):$(id -g)" -e KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32" \
        -e KMS_MASTER_PASSWORD_FILE=/mpw/master_password -v "$MPW:/mpw:ro" \
        -v "$C:/proj" -w /proj/cache-agent --entrypoint /opt/venv/bin/python "$IMG" -c '
import supervisor
env = supervisor.settings(); supervisor.ensure_login(env); supervisor.fetch(env)
print("FETCH_DONE")' 2>&1 | tee -a "$OUT"; }

# R1 + R2 — the fresh kms: every key is missing
o="$(agent)"
A="$(kget shared/anthropic ANTHROPIC_API_KEY)"
grep -q FETCH_DONE <<< "$o" && grep -q 'ANTHROPIC_API_KEY, REDIS_PASSWORD: not in kms — registering with an initial random value' <<< "$o" \
  && grep -q 'ANTHROPIC_API_KEY → kv/shared/anthropic: initial PLACEHOLDER' <<< "$o" && grep -q 'ANTHROPIC_API_KEY ← kms (shared/anthropic)   ⚠ placeholder' <<< "$o" \
  && grep -q 'REDIS_PASSWORD ← kms (mycache/redis)$' <<< "$o" && ! grep -qE 'add it: bash|set it in the kms UI' <<< "$o" \
    && ok "R1 fresh kms: the 2 missing keys registered by its own script in one go, every key fetched, the placeholder named" \
    || fail "R1 [$(grep -E 'ERROR|not in kms|registering|placeholder' <<< "$o" | head -4 | tr '\n' '¦')]"
[[ "$A" =~ ^placeholder-[A-Za-z0-9]{32}$ ]] && [ "$(knote shared/anthropic ANTHROPIC_API_KEY)" = "placeholder;v1;mycache-cache-agent;$TODAY" ] \
    && ok "R2 in kms: placeholder-<32 random> · note initial_ANTHROPIC_API_KEY = placeholder;v1;mycache-cache-agent;$TODAY" \
    || fail "R2 value-shape=$([[ "$A" =~ ^placeholder- ]] && echo placeholder || echo other) note=$(knote shared/anthropic ANTHROPIC_API_KEY)"

# R3 an own password missing (its entry deleted) → random
curl -s -o /dev/null -X DELETE -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/metadata/mycache/redis"
o="$(agent)"; G="$(kget mycache/redis REDIS_PASSWORD)"
grep -q FETCH_DONE <<< "$o" && grep -q 'REDIS_PASSWORD: not in kms' <<< "$o" && [[ "$G" =~ ^[A-Za-z0-9]{32}$ ]] \
  && [ "$(knote mycache/redis REDIS_PASSWORD)" = "random;v1;mycache-cache-agent;$TODAY" ] && [ "$(kget shared/anthropic ANTHROPIC_API_KEY)" = "$A" ] \
    && ok "R3 an own password missing → a RANDOM value (32 letters/digits), note 'random'; the placeholder elsewhere untouched" \
    || fail "R3 [$(grep -E 'ERROR|not in kms' <<< "$o" | head -2 | tr '\n' '¦')] note=$(knote mycache/redis REDIS_PASSWORD)"

# R4 a second fetch → nothing registered
o="$(agent)"; grep -q FETCH_DONE <<< "$o" && ! grep -q 'registering' <<< "$o" && ok "R4 a second fetch → nothing registered" || fail "R4 [$(tail -3 <<< "$o" | tr '\n' '¦')]"

# R5 your own value is never overwritten
REAL="sk-real-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s' "$REAL" | python3 -c 'import sys,json; print(json.dumps({"data":{"ANTHROPIC_API_KEY":sys.stdin.read()}}))' \
    | curl -s -o /dev/null -X POST -H @<(printf 'X-Vault-Token: %s\n' "$TOK") --data @- "$U/v1/kv/data/shared/anthropic"
v0="$(kver shared/anthropic)"
o5="$(KMS_TOKEN="$TOK" KMS_URL="$U" REG_AGENT_CONF="$C/cache-agent/agent.conf" bash "$KD/register_kms_cache_keys_with_random_initial.sh" ANTHROPIC_API_KEY 2>&1)"; rc5=$?
echo "$o5" >> "$OUT"
[ $rc5 = 0 ] && grep -q 'ANTHROPIC_API_KEY → kv/shared/anthropic: already in kms — left as it is' <<< "$o5" && grep -q '0 created · 1 already there' <<< "$o5" \
  && [ "$(kget shared/anthropic ANTHROPIC_API_KEY)" = "$REAL" ] && [ "$(kver shared/anthropic)" = "$v0" ] \
    && ok "R5 by hand, your value already in kms → 'already in kms', value + version unchanged (never overwritten)" \
    || fail "R5 rc=$rc5 [$(tail -2 <<< "$o5" | tr '\n' '¦')]"

# R6 a key missing + master_password empty → one line, exit 1, nothing written
curl -s -o /dev/null -X DELETE -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/metadata/mycache/redis"
: > "$MPW/master_password"; o="$(agent)"
! grep -q FETCH_DONE <<< "$o" && grep -q "kms's master_password is empty — put your kms password into" <<< "$o" \
  && grep -q 'register_kms_cache_keys_with_random_initial.sh REDIS_PASSWORD' <<< "$o" && [ -z "$(kget mycache/redis REDIS_PASSWORD)" ] \
    && ok "R6 a key missing + master_password empty → one line naming the file + the by-hand command, stops, nothing written" \
    || fail "R6 [$(grep -E 'ERROR' <<< "$o" | head -2 | tr '\n' '¦')]"
printf '%s\n' "$PW" > "$MPW/master_password"

# R8 the all-keys mode: two entries gone → registered, the other keys "already in kms"
for e in mycache/redis; do curl -s -o /dev/null -X DELETE -H @<(printf 'X-Vault-Token: %s\n' "$TOK") "$U/v1/kv/metadata/$e"; done
o8="$(KMS_TOKEN="$TOK" REG_AGENT_CONF="$C/cache-agent/agent.conf" bash "$KD/register_kms_cache_keys_with_random_initial.sh" 2>&1)"; rc8=$?
echo "$o8" >> "$OUT"
[ $rc8 = 0 ] && grep -q 'keys: ANTHROPIC_API_KEY REDIS_PASSWORD' <<< "$o8" \
  && grep -q '1 created · 1 already there' <<< "$o8" && [ -n "$(kget mycache/redis REDIS_PASSWORD)" ] \
    && ok "R8 no names = every kms line of agent.conf: the missing one created, the 1 other(s) 'already in kms'" || fail "R8 rc=$rc8 [$(tail -3 <<< "$o8" | tr '\n' '¦')]"

# R9 kms's base once: only the KMS_URL line points at the throwaway kms — every key was still found there
[ "$(grep -c "$U" "$C/cache-agent/agent.conf")" = 1 ] && [ "$(grep -cE '^[A-Z_]+=\$\{KMS_URL\}/v1/kv/data/' "$C/cache-agent/agent.conf")" = 2 ] \
    && ok "R9 kms's base is ONE line (KMS_URL) — the 2 keys (\${KMS_URL}/…) all reached the throwaway kms through it" || fail "R9 base lines=$(grep -c "$U" "$C/cache-agent/agent.conf")"

# R7 nothing secret in any output
{ grep -qF -- "$TOK" "$OUT" || grep -qF -- "$PW" "$OUT" || grep -qF -- "$A" "$OUT" || grep -qF -- "$G" "$OUT" || grep -qF -- "$REAL" "$OUT"; } \
    && fail "R7 a value / token / password appeared in the output" || ok "R7 no value, token or password in any output"
unset TOK PW S1 S2 A G REAL

[ "$(stat -c '%n %s %Y' "$RWS/projectspace/mycache/cache-agent/connect_external/kms/credentials"/*/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/* "$RWS/mountspace/usb/myworkspace/projectspace/kms"/*/* 2>/dev/null | sort)" = "$REAL_STATE" ] \
    && ok "the real credentials/ and usb/ are untouched" || fail "a REAL file changed — check credentials/ and mountspace/usb/"
[ $FAIL = 0 ] && ok "register-missing-keys tests passed (throwaway kms removed)" || { echo "  some checks failed"; exit 1; }
