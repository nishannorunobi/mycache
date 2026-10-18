#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# register_kms_keys_when_missing_with_random_initial.sh — keys the cache-agent needs but kms does not have → created
#                                                          there with an initial random value (owner rule, 2026-10-17)
#
# What for    Every key is generated in kms automatically; you change the value later by hand in the kms UI. The
#             cache-agent runs this when its fetch finds a key missing — a fresh kms never stops Redis.
# Who         cache-agent/supervisor.py (start: the keys its fetch could not find) — or you, by hand.
# How         bash cache-agent/connect_external/kms/register_kms_keys_when_missing_with_random_initial.sh KEY [KEY …]
#             bash cache-agent/connect_external/kms/register_kms_keys_when_missing_with_random_initial.sh
#             KEY = a name in agent.conf whose value is a kms address (${KMS_URL}/v1/kv/data/<entry>[#OTHER_KEY]);
#             no KEY = ALL of them — every kms line of agent.conf (svcmgt/register_all_kms_keys.sh at the start)
# Steps       1. owner login: KMS_TOKEN (handed over by the agent) · else kms's master_password (KMS_MASTER_PASSWORD_FILE)
#                · else asked in a terminal · else one line, exit 1 — the agent's own login can only READ
#             2. per entry: a key already there → left as it is (never overwritten) · missing → a new random value;
#                one from an outside service (*_API_KEY, *_TOKEN, SMTP_PASS) → "placeholder-<random>" (it cannot work
#                until you put the real one in) · the entry's other keys are kept
#             3. kms's note on the entry (custom metadata, never a value): initial_<KEY> = <random|placeholder>;v<version>;
#                <by>;<date> — kms's secret_age.sh (every startup) lists it until you change the value
#             4. the owner login is revoked (when this script made it)
# Output      [  OK  ] ANTHROPIC_API_KEY → kv/shared/anthropic: initial PLACEHOLDER (an outside key) — version 1
#             [ WARN ] set your real one: kms UI → kv → shared/anthropic, or kms's set_secret.sh shared/anthropic ANTHROPIC_API_KEY
#             [  OK  ] 1 created · 0 already there · values never shown
# Errors      no owner login → "put your kms password into …/master_password, or run this by hand"
#             a key that IS in kms but the agent may not read it → named: run signup_with_kms.sh again
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
ask() { { printf '%s' "$1" > /dev/tty; } 2>/dev/null || printf '%s' "$1" >&2; }
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
info() { echo -e "\033[36m[ INFO ]\033[0m $*"; }
warn() { echo -e "\033[33m[ WARN ]\033[0m $*"; }
bad()  { echo -e "\033[31m[ERROR]\033[0m  $*"; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"
OWNER="${KMS_OWNER:-nishan}"
BY="${KMS_REGISTER_BY:-mycache-cache-agent}"            # who asked — kept in kms's note
source "$HERE/kms_conf.sh"                                  # the config lines with ${KMS_URL} expanded (TESTSERVER-46)
CONF="$(kms_conf "$ENV_FILE")"
# no names → every key whose value is a kms address (the component's own list — nothing else is ever registered)
[ $# -gt 0 ] || set -- $(printf '%s\n' "$CONF" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=https?://[^ ]+/v1/kv/data/' | cut -d= -f1)
[ $# -gt 0 ] || { bad "$(basename "$ENV_FILE") names no kms address — nothing to register"; exit 1; }
# kms as agent.conf names it (KMS_URL, else the first full address on a setting line); KMS_URL from the caller wins
URL="${KMS_URL:-$(kms_base "$ENV_FILE")}"
[ -n "$URL" ] || { bad "agent.conf names no kms address — nothing registered"; exit 1; }
h="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/v1/sys/health")"
[ "$h" = 200 ] || { bad "kms at $URL is not running + unsealed (health ${h:-none})"; exit 1; }
info "asked by: $BY · keys: $*"

# 1. the owner login
MINE=
if [ -n "${KMS_TOKEN:-}" ]; then TOKEN="$KMS_TOKEN"; info "kms owner login: handed over"
else
    PWF="${KMS_MASTER_PASSWORD_FILE:-}"
    if grep -q '[^[:space:]]' "$PWF" 2>/dev/null; then SRC="kms's master_password"; PW_IN() { head -1 "$PWF" | tr -d '\r\n'; }
    elif { : </dev/tty; } 2>/dev/null; then SRC="typed"; ask "kms password for $OWNER (hidden): "; read -r -s _pw </dev/tty; echo >&2; PW_IN() { printf '%s' "$_pw"; }
    else bad "no kms owner login — put your kms password into kms's master_password (mountspace/usb/myworkspace/projectspace/kms/master_password/master_password), or run by hand: bash $0 $*"; exit 1; fi
    TOKEN="$(PW_IN | python3 -c 'import sys,json; print(json.dumps({"password": sys.stdin.read()}))' \
        | curl -s --max-time 10 -X POST --data @- "$URL/v1/auth/userpass/login/$OWNER" \
        | python3 -c 'import sys,json; print((json.load(sys.stdin).get("auth") or {}).get("client_token",""))' 2>/dev/null)"
    unset _pw; MINE=1
    [ -n "$TOKEN" ] || { bad "kms refused the owner login ($SRC) — check it"; exit 1; }
    info "kms owner login: from $SRC"
fi
trap '[ -n "$MINE" ] && curl -s -o /dev/null -X POST -H @<(printf "X-Vault-Token: %s\n" "$TOKEN") "$URL/v1/auth/token/revoke-self"; unset TOKEN' EXIT

# 2 + 3. per key: its entry + key inside (from agent.conf), create what is missing, note it — values only inside python
PAIRS=""
for K in "$@"; do
    A="$(printf '%s\n' "$CONF" | grep -E "^$K=" | head -1 | cut -d= -f2-)"
    [[ "$A" =~ /v1/kv/data/([^#[:space:]]+)(#([A-Za-z_][A-Za-z0-9_]*))?$ ]] || { warn "$K is not a kms address in $(basename "$ENV_FILE") — skipped"; continue; }
    PAIRS+="$K ${BASH_REMATCH[1]} ${BASH_REMATCH[3]:-$K}"$'\n'
done
[ -n "$PAIRS" ] || { bad "none of the keys is a kms address — nothing registered"; exit 1; }
printf '%s' "$PAIRS" | TOKEN="$TOKEN" URL="$URL" BY="$BY" python3 -c '
import json, os, secrets, string, sys, urllib.request, urllib.error
from datetime import date
url, tok, by = os.environ["URL"], os.environ["TOKEN"], os.environ["BY"]
def call(method, path, body=None):
    req = urllib.request.Request(f"{url}/v1/{path}", method=method, data=None if body is None else json.dumps(body).encode(),
                                 headers={"X-Vault-Token": tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404: return {}
        raise
outside = lambda k: k.endswith("_API_KEY") or k.endswith("_TOKEN") or k == "SMTP_PASS"
rand = lambda: "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))
todo = {}
for line in sys.stdin.read().splitlines():
    name, entry, key = line.split()
    todo.setdefault(entry, []).append((name, key))
made = kept = 0
for entry, keys in todo.items():
    cur = (call("GET", f"kv/data/{entry}").get("data") or {}).get("data") or {}
    new = {key: ("placeholder-" + rand() if outside(key) else rand()) for name, key in keys if key not in cur}
    for name, key in keys:
        if key in cur:
            kept += 1
            print(f"OK|{name} → kv/{entry}: already in kms — left as it is (if the agent still cannot read it: run signup_with_kms.sh again)")
    if not new: continue
    md = call("GET", f"kv/metadata/{entry}").get("data") or {}
    before = str(md.get("current_version", ""))
    ver = (call("POST", f"kv/data/{entry}", {"data": {**cur, **new}}).get("data") or {}).get("version")
    note = dict(md.get("custom_metadata") or {})
    for k, v in list(note.items()):                     # earlier initial keys still unchanged → they stay "initial"
        f = (v or "").split(";")
        if k.startswith("initial_") and len(f) == 4 and f[1] == f"v{before}": note[k] = ";".join([f[0], f"v{ver}", f[2], f[3]])
    for key in new:
        note[f"initial_{key}"] = ";".join(["placeholder" if outside(key) else "random", f"v{ver}", by, date.today().isoformat()])
    call("POST", f"kv/metadata/{entry}", {"custom_metadata": note})
    for name, key in keys:
        if key not in new: continue
        made += 1
        if outside(key):
            print(f"OK|{name} → kv/{entry}: initial PLACEHOLDER (an outside key) — version {ver}")
            print(f"WARN|set your real one: kms UI → kv → {entry}, or kms\x27s set_secret.sh {entry} {key}")
        else:
            print(f"OK|{name} → kv/{entry}: initial RANDOM value — version {ver} (fine to keep; change any time in the kms UI)")
print(f"SUM|{made}|{kept}")
' | while IFS='|' read -r kind a b; do
    case "$kind" in OK) ok "$a" ;; WARN) warn "$a" ;; SUM) ok "$a created · $b already there · values never shown" ;; esac
done
[ "${PIPESTATUS[1]}" = 0 ] || { bad "kms refused a write — nothing more done"; exit 1; }
