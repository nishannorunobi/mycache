#!/bin/bash
# ────────────────────────────────────────────────────────
# test_credentials.sh — automatic tests of mycache's issued credentials (issued_credentials/), on a THROWAWAY kms only
#
# What for    Prove the Redis password's rotation reminder (CONFMGT [8.6]): silent while more than WARN_BEFORE_DAYS
#             are left · ⚠ + "do:" within them · ⚠ overdue (a reminder, never "expired") · the right "cannot tell"
#             lines — without ever touching the real kms, the real login, the real password or the running stack.
# Who         Claude (auto test in the branch, then on main) · the owner by hand.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/test_credentials.sh   (~30 s · throwaway kms on :8122)
# Cases       C0 static: every .sh answers --help, bash -n, the .py compile · start.sh / stop.sh call credentials_check.sh
#                (never failing: || true) · the runner finds *_check.sh by itself
#             C1 fine (90-day rule, written today): by hand OK + "rotate by", exit 0 · --quiet + the runner: nothing, exit 0
#             C2 within the window (a 3-day rule): exit 1, WARN "rotate in 3 days" + "do: bash …redis_password_rotate.sh" ·
#                the runner shows it, exit 1
#             C3 overdue ("today" = 100 days on): exit 1 (never 2), WARN "overdue by 10 days … nothing stops" + "do:"
#             C4 kms down: exit 3, WARN, never the real kms (KMS_URL set = the only one tried)
#             C5 not signed up: exit 3, WARN + the sign-up line
#             C6 credentials.conf missing / garbage → 7 and 90 + a WARN each
#             C7 SECRET_MGT=local → OK "no kms date", exit 0 · L1 the password never on screen
# Errors      [ERROR] <case> … — FAILED at the end, exit 1
# ────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/ccc/scripts/lib/create_logging_path.sh" ]; then
    source "$_WS_ROOT/ccc/scripts/lib/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; AGENT="$(dirname "$HERE")"; PROJ="$(dirname "$AGENT")"
KMSP="$_WS_ROOT/projectspace/platform/kms"; DS="$KMSP/dockerspace"
OPENBAO_IMAGE="$(grep -E '^OPENBAO_IMAGE=' "$DS/.env" | cut -d= -f2-)"   # only the image — never kms's folders
T=kms-credentials-test; PORT=8122; U=http://127.0.0.1:$PORT; ROLE=mycache-cache-agent
FAIL=0
ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*"; FAIL=1; }
j()   { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

# ── a throwaway workspace: the code under test copied in, its own creds, nothing real ─────────────────────
TMP="$(mktemp -d)"; DATA="$(mktemp -d)"; AUDIT="$(mktemp -d)"
cleanup() { docker rm -f "$T" >/dev/null 2>&1; rm -rf "$TMP" "$DATA" "$AUDIT"; }
trap cleanup EXIT
W="$TMP/ws"; A="$W/projectspace/platform/mycache/cache-agent"; C="$A/issued_credentials"
mkdir -p "$W/mountspace" "$C" "$A/connect_external/kms"
cp "$HERE"/*.sh "$HERE"/*.py "$HERE/credentials.conf" "$C/"
cp "$AGENT/connect_external/kms/kms_transfer.py" "$A/connect_external/kms/"
conf() { printf 'KMS_URL=%s\nSECRET_MGT=%s\nREDIS_PASSWORD=${KMS_URL}/v1/kv/data/mycache/redis\n' "$U" "${1:-kms}" > "$A/agent.conf"; }
rules() { printf 'WARN_BEFORE_DAYS=%s\nROTATE_AFTER_DAYS=%s\n' "$1" "$2" > "$C/credentials.conf"; }
conf; rules 7 90
export KMS_URL="$U" KMS_APPROLE_DIR="$TMP/approle"
CRED="$KMS_APPROLE_DIR/$ROLE"; mkdir -p "$CRED"; chmod 700 "$KMS_APPROLE_DIR" "$CRED"
export KMS_STATE_DIR="$TMP/state" KMS_SECRETS_DIR="$TMP/secrets/kms" KMS_ALLOWED_CIDRS="172.16.0.0/12,127.0.0.1/32"
export KMS_STATIC_KEY_DIR="$TMP/usb" KMS_USB_BACKUP_DIR="$TMP/usbbk" KMS_MASTER_PASSWORD_FILE="$TMP/master_password"

# ── C0 static (the real files) ───────────────────────────────────────────────
s=""
for f in "$HERE"/*.sh; do bash -n "$f" || s+=" $(basename "$f"):syntax"; bash "$f" --help 2>/dev/null | head -1 | grep -q . || s+=" $(basename "$f"):--help"; done
python3 -c 'import sys; [compile(open(f).read(), f, "exec") for f in sys.argv[1:]]' "$HERE"/*.py 2>/dev/null || s+=" py-compile"
for f in start.sh stop.sh; do grep -q 'cache-agent/issued_credentials/credentials_check.sh" || true' "$PROJ/$f" || s+=" $f:call"; done
grep -q '"\$HERE"/\*_check.sh' "$HERE/credentials_check.sh" || s+=" runner:discovery"
[ -z "$s" ] && ok "C0 static: --help · syntax · start/stop call credentials_check.sh (|| true) · the runner finds *_check.sh" \
    || bad "C0 static:$s"

# ── throwaway kms ────────────────────────────────────────────────────────────
docker rm -f "$T" >/dev/null 2>&1
docker run -d --name "$T" -p 127.0.0.1:$PORT:8200 --user "$(id -u):$(id -g)" -e SKIP_CHOWN=true \
    -v "$DS/config:/openbao/config:ro" -v "$DATA:/openbao/data" -v "$AUDIT:/openbao/audit" \
    "$OPENBAO_IMAGE" server >/dev/null || { bad "throwaway kms did not start"; exit 1; }
health() { curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$U/v1/sys/health"; }
for _ in $(seq 1 30); do [ "$(health)" = 501 ] && break; sleep 1; done
INIT="$(printf '{"secret_shares":3,"secret_threshold":2}' | curl -s -X PUT --data @- "$U/v1/sys/init")"
S1="$(echo "$INIT" | j 'd["keys_base64"][0]')"; S2="$(echo "$INIT" | j 'd["keys_base64"][1]')"; unset INIT
for k in "$S1" "$S2"; do printf '{"key":"%s"}' "$k" | curl -s -X PUT --data @- "$U/v1/sys/unseal" >/dev/null; done
for _ in $(seq 1 30); do [ "$(health)" = 200 ] && break; sleep 1; done
PW="pw-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s\n%s\n%s\n%s\n' "$S1" "$S2" "$PW" "$PW" | bash "$KMSP/bootstrap.sh" >/dev/null 2>&1 || { bad "bootstrap failed"; exit 1; }
OT="$(printf '%s' "$PW" | python3 -c 'import sys,json; print(json.dumps({"password":sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$U/v1/auth/userpass/login/nishan" | j 'd["auth"]["client_token"]')"
[ -n "$OT" ] || { bad "owner login on the throwaway kms failed"; exit 1; }
api() { curl -s -H "X-Vault-Token: $OT" -X "$1" ${3:+--data "$3"} "$U/v1/$2"; }
# the entry (written today) · mycache's login as its sign-up makes it: read kv/data/mycache/*
RP="redis-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
api POST kv/data/mycache/redis "{\"data\":{\"REDIS_PASSWORD\":\"$RP\"}}" >/dev/null
api PUT "sys/policies/acl/$ROLE" '{"policy":"path \"kv/data/mycache/redis\" { capabilities = [\"read\"] }\npath \"kv/data/mycache/redis/*\" { capabilities = [\"read\"] }\n"}' >/dev/null
api POST "auth/approle/role/$ROLE" "{\"token_policies\":\"$ROLE\",\"token_ttl\":\"1h\"}" >/dev/null
api GET "auth/approle/role/$ROLE/role-id" | j 'd["data"]["role_id"]' > "$CRED/role_id"
api POST "auth/approle/role/$ROLE/secret-id" '{}' | j 'd["data"]["secret_id"]' > "$CRED/secret_id"
chmod 600 "$CRED/role_id" "$CRED/secret_id"
TODAY="$(date +%F)"; DUE90="$(date -d "$TODAY + 90 days" +%F)"
run() { OUT="$("$@" 2>&1)"; RC=$?; ALL+="$OUT"$'\n'; }
ALL=""
CHK="$C/redis_password_rotation_check.sh"; RUNNER="$C/credentials_check.sh"

# C1 fine
run bash "$CHK"
{ [ "$RC" = 0 ] && grep -q "Redis password changed $TODAY — rotate by $DUE90, 90 days left (reminds at 7)" <<< "$OUT"; } \
    && ok "C1 fine: by hand → OK, changed $TODAY, rotate by $DUE90" || bad "C1 by hand: rc=$RC $OUT"
run bash "$CHK" --quiet; { [ "$RC" = 0 ] && [ -z "$OUT" ]; } && ok "C1 --quiet: nothing printed, exit 0" || bad "C1 --quiet: rc=$RC '$OUT'"
run bash "$RUNNER";      { [ "$RC" = 0 ] && [ -z "$OUT" ]; } && ok "C1 credentials_check.sh (start/stop): silent, exit 0" || bad "C1 runner: rc=$RC '$OUT'"

# C2 within the window
rules 7 3
run bash "$CHK" --quiet
{ [ "$RC" = 1 ] && grep -q 'Redis password: rotate in 3 days (due .* · 3-day rule)' <<< "$OUT" && grep -q 'do: bash .*issued_credentials/redis_password_rotate.sh' <<< "$OUT"; } \
    && ok "C2 within 7 days: exit 1, WARN rotate in 3 days + do: …redis_password_rotate.sh" || bad "C2: rc=$RC $OUT"
run bash "$RUNNER"; { [ "$RC" = 1 ] && grep -q 'rotate in 3 days' <<< "$OUT"; } && ok "C2 the runner shows it, exit 1" || bad "C2 runner: rc=$RC $OUT"

# C3 overdue
rules 7 90
run env CREDENTIALS_CHECK_TODAY="$(date -d "$TODAY + 100 days" +%F)" bash "$CHK" --quiet
{ [ "$RC" = 1 ] && grep -q 'rotation overdue by 10 days (was due .* · 90-day rule) — nothing stops' <<< "$OUT" && grep -q 'do: bash' <<< "$OUT"; } \
    && ok "C3 overdue: exit 1 (a reminder, never 2), WARN overdue by 10 days + do:" || bad "C3: rc=$RC $OUT"

# C4 kms down
run env KMS_URL=http://127.0.0.1:1 bash "$CHK" --quiet
{ [ "$RC" = 3 ] && grep -q 'kms does not answer' <<< "$OUT"; } && ok "C4 kms down: exit 3, WARN — never the real kms" || bad "C4: rc=$RC $OUT"

# C5 not signed up
run env KMS_APPROLE_DIR="$TMP/none" bash "$CHK" --quiet
{ [ "$RC" = 3 ] && grep -q 'no kms login yet .*signup_with_kms.sh' <<< "$OUT"; } && ok "C5 not signed up: exit 3, WARN + the sign-up line" || bad "C5: rc=$RC $OUT"

# C6 credentials.conf missing / garbage
rm -f "$C/credentials.conf"; run bash "$CHK"
{ [ "$RC" = 0 ] && grep -q 'WARN_BEFORE_DAYS is missing — using 7' <<< "$OUT" && grep -q 'ROTATE_AFTER_DAYS is missing — using 90' <<< "$OUT" && grep -q "rotate by $DUE90" <<< "$OUT"; } \
    && ok "C6 credentials.conf missing → 7 and 90 + a WARN each" || bad "C6 missing: rc=$RC $OUT"
rules x y; run bash "$CHK"
{ grep -q "WARN_BEFORE_DAYS is 'x' — using 7" <<< "$OUT" && grep -q "ROTATE_AFTER_DAYS is 'y' — using 90" <<< "$OUT"; } \
    && ok "C6 garbage → 7 and 90 + a WARN each" || bad "C6 garbage: rc=$RC $OUT"
rules 7 90

# C7 SECRET_MGT=local
conf local; run bash "$CHK"
{ [ "$RC" = 0 ] && grep -q 'SECRET_MGT is not kms — no kms date' <<< "$OUT"; } && ok "C7 SECRET_MGT=local → OK, no kms date, exit 0" || bad "C7: rc=$RC $OUT"
conf

# L1 nothing secret on screen
{ ! grep -qF "$RP" <<< "$ALL" && ! grep -qF "$(cat "$CRED/secret_id")" <<< "$ALL"; } && ok "L1 the password and the login never on screen" || bad "L1 a secret was printed"

[ "$FAIL" = 0 ] && { ok "ALL PASS"; exit 0; } || { bad "FAILED"; exit 1; }
