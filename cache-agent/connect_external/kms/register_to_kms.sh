#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# register_to_kms.sh — sign the cache-agent up with kms (once)
#
# What for    The agent is its own component: it needs its own kms login.
#
# Who         The kms owner (asks the kms password). Re-running is safe — nothing changes.
#
# How         bash cache-agent/connect_external/kms/register_to_kms.sh
#
# Steps       1. log in to kms as the owner
#             2. policy + AppRole mycache-cache-agent → may READ:
#                kv/mycache/cache-agent · kv/mycache/redis · kv/shared/anthropic
#             3. login files → credentials/mycache-cache-agent/ (git-ignored, 600)
#             4. first time: copy ANTHROPIC_API_KEY from agent.conf into kms
#
# Output      [  OK  ] cache-agent registered with kms
#
# Next        bash cache-agent/host_start.sh
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT="$(cd "$HERE/../.." && pwd)"
ENV_FILE="${REG_AGENT_CONF:-$AGENT/agent.conf}"                 # REG_*: tests point elsewhere
[ -f "$ENV_FILE" ] && source <(grep -E '^KMS_(URL|APPROLE_DIR)=' "$ENV_FILE")
URL="${KMS_URL:-http://127.0.0.1:8110}"
CRED="${KMS_APPROLE_DIR:-}"; [ -n "$CRED" ] || CRED="$HERE/credentials"
CIDRS="${KMS_ALLOWED_CIDRS:-172.28.0.0/16,127.0.0.1/32}"        # logins only from this PC / its Docker network
OWNER="${KMS_OWNER:-nishan}"

# what mycache needs from kms: part → kv paths it may read
declare -A READS=(
    [cache-agent]="mycache/cache-agent mycache/redis shared/anthropic"
)
# secrets to copy into kms the first time: kv path · key · local file
MOVES=(
    "shared/anthropic ANTHROPIC_API_KEY $ENV_FILE"
)

ok()  { echo -e "\033[32m[  OK  ]\033[0m $*"; }
bad() { echo -e "\033[31m[ERROR]\033[0m  $*" >&2; }
call() {   # call METHOD PATH  (JSON body from stdin for POST/PUT) → response body
    local m="$1" p="$2"
    if [ "$m" = GET ] || [ "$m" = LIST ]; then curl -s -X "$m" -H @<(printf 'X-Vault-Token: %s\n' "$TOKEN") "$URL/v1/$p"
    else curl -s -X "$m" -H @<(printf 'X-Vault-Token: %s\n' "$TOKEN") --data @- "$URL/v1/$p"; fi
}
code() { local m="$1" p="$2"; curl -s -o /dev/null -w '%{http_code}' -X "$m" -H @<(printf 'X-Vault-Token: %s\n' "$TOKEN") --data @- "$URL/v1/$p"; }
jget() { python3 -c 'import sys,json
d=json.load(sys.stdin)
for k in sys.argv[1:]: d=d.get(k) if isinstance(d,dict) else None
print("" if d is None else d)' "$@" 2>/dev/null; }

h="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/v1/sys/health")"
[ "$h" = 200 ] || { bad "kms at $URL is not running + unsealed (health ${h:-none})"; exit 1; }

# ── owner login (password hidden, sent via stdin) ─────────────────────────────
read -r -s -p "kms password for $OWNER (hidden): " pw; echo >&2
TOKEN="$(printf '%s' "$pw" | python3 -c 'import sys,json; print(json.dumps({"password": sys.stdin.read()}))' \
    | curl -s -X POST --data @- "$URL/v1/auth/userpass/login/$OWNER" | jget auth client_token)"
unset pw
[ -n "$TOKEN" ] || { bad "kms login failed for $OWNER"; exit 1; }
trap 'printf "{}" | code POST auth/token/revoke-self >/dev/null; unset TOKEN' EXIT
umask 077

# ── 1 + 2: policy, AppRole and login files per part ───────────────────────────
mkdir -p "$CRED" && chmod 700 "$CRED"
for part in "${!READS[@]}"; do
    name="mycache-$part"; hcl=""
    for p in ${READS[$part]}; do
        hcl+="path \"kv/data/$p\" { capabilities = [\"read\"] }"$'\n'"path \"kv/data/$p/*\" { capabilities = [\"read\"] }"$'\n'
    done
    printf '%s' "$hcl" | python3 -c 'import sys,json; print(json.dumps({"policy": sys.stdin.read()}))' \
        | code PUT "sys/policies/acl/$name" | grep -q '^20' || { bad "policy $name failed"; exit 1; }
    printf '{"token_policies":"%s","token_ttl":"1h","token_max_ttl":"4h","secret_id_bound_cidrs":"%s","token_bound_cidrs":"%s"}' \
        "$name" "$CIDRS" "$CIDRS" | code POST "auth/approle/role/$name" | grep -q '^20' || { bad "AppRole $name failed"; exit 1; }
    d="$CRED/$name"; mkdir -p "$d" && chmod 700 "$d"
    call GET "auth/approle/role/$name/role-id" | jget data role_id > "$d/role_id"
    if [ ! -s "$d/secret_id" ]; then
        printf '{}' | call POST "auth/approle/role/$name/secret-id" | jget data secret_id > "$d/secret_id.new" \
            && [ -s "$d/secret_id.new" ] && mv "$d/secret_id.new" "$d/secret_id" \
            || { rm -f "$d/secret_id.new"; bad "secret_id for $name failed"; exit 1; }
        sid="new login"
    else sid="login kept"; fi
    chmod 600 "$d/role_id" "$d/secret_id"
    ok "$name — may read: ${READS[$part]} · $sid"
done

# ── 3: first time, copy secrets that are still in local files into kms ─────────
for m in "${MOVES[@]}"; do
    read -r kpath key file <<< "$m"
    cur="$(call GET "kv/data/$kpath" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps((d.get("data") or {}).get("data") or {}))' 2>/dev/null)"
    [ -n "$cur" ] || cur='{}'
    if printf '%s' "$cur" | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin).get(sys.argv[1]) else 1)' "$key"; then
        ok "kv/$kpath $key already in kms"; continue
    fi
    val="$( [ -r "$file" ] && python3 - "$file" "$key" <<'PY'
import sys, re, shlex
path, key = sys.argv[1], sys.argv[2]
for line in open(path):
    m = re.match(r'^\s*(?:export\s+)?' + re.escape(key) + r'\s*=\s*(.*?)\s*$', line)
    if m:
        v = m.group(1)
        try: v = shlex.split(v, comments=True)[0] if v else ""
        except Exception: pass
        if v and not v.startswith("<"): sys.stdout.write(v)
        break
PY
)"
    if [ -z "$val" ]; then echo -e "\033[33m[WARN]\033[0m   $key is not in kms and not in $(basename "$file") — set it in the kms UI: kv/$kpath"; continue; fi
    printf '%s\n%s' "$cur" "$val" | python3 -c 'import sys,json
cur=json.loads(sys.stdin.readline()); cur[sys.argv[1]]=sys.stdin.read(); print(json.dumps({"data": cur}))' "$key" \
        | code POST "kv/data/$kpath" | grep -q '^20' && ok "kv/$kpath $key copied into kms from $(basename "$file")" \
        || { unset val; bad "could not store $key"; exit 1; }
    unset val
done
ok "cache-agent registered with kms — start it: bash cache-agent/host_start.sh"
