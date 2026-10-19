#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_local2kms.sh — mycache (cache-agent): every plain password in agent.conf sent to kms, the kms addresses
#                                 back on the lines · SECRET_MGT=kms (TESTSERVER-75)
#
# What for    "kms deploy": back from local — each line under its "# kms: <address>" comment: the key missing in kms →
#             added · there but different → kms updated from the local value (a new version) · the same → left.
# Who         You — or svcmgt/transfer_all_local2kms.sh (every component, one kms login).
# How         bash cache-agent/connect_external/kms/cache_transfer_local2kms.sh      (asks your kms password; safe to run again)
# Steps       1. SECRET_MGT already kms → nothing to do
#             2. each value → kms (one write per entry, its other keys kept); empty / NOT_FOUND_IN_KMS → not sent (+ WARN)
#             3. the address from the comment back on each line · SECRET_MGT=kms
# Output      [  OK  ] <KEY> → kv/<entry>: kms updated from the local value  (values are never shown)
#             [  OK  ] local → kms: 0 added · 1 updated · 1 the same · 0 not sent — SECRET_MGT=kms; …
# Errors      kms not running · login refused · a write refused → one line, the config unchanged
# Next        restart the component (its own start) — it then fetches from kms again
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"                 # REG_*: tests point elsewhere
export KMS_MASTER_PASSWORD_FILE="${KMS_MASTER_PASSWORD_FILE:-$_WS_ROOT/mountspace/usb/myworkspace/projectspace/kms/master_password/master_password}"
python3 "$HERE/kms_transfer.py" local2kms --mode-conf "$CONF" --conf "$CONF"; rc=$?
# step 3 of the rotation done → this component fetches from kms at its next start; no kms login yet → say how (TESTSERVER-94)
if [ $rc = 0 ] && ! ls "${KMS_CREDENTIALS_DIR:-$HERE/credentials}"/*/secret_id >/dev/null 2>&1; then
    echo -e "\033[36m[ INFO ]\033[0m next: sign this component up with kms (once): bash $HERE/signup_with_kms.sh"
fi
exit $rc
