#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_config_secret_mgt_kms.sh — mycache (cache-agent): CONFIG SECRET_MGT=kms — only that line (TESTSERVER-110)
#
# What for    Switches this component to kms: at its next start it fetches its passwords from kms. It changes nothing
#             else. Before: cache_transfer_local2kms.sh (values → kms) and cache_transfer_comment2local_kmsurl.sh
#             (the fields ← their kms addresses).
# Who         You — or svcmgt/config_all_secret_mgt_kms.sh (every component; also svc_policy.conf's SECRET_MGT).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_config_secret_mgt_kms.sh      (safe to run again)
# Steps       1. a field that is not its kms address yet → refused, nothing changed
#             2. kms reachable + a login (master_password file, else asked) → every key must be in kms, else refused ·
#                kms not reachable / no login → switched anyway + WARN
#             3. SECRET_MGT=kms · no kms login for this component yet → how to sign it up (signup_with_kms.sh)
# Output      [  OK  ] SECRET_MGT=kms (was local) — fetches from kms at its next start
# Next        restart the component
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
python3 "$HERE/kms_transfer.py" modekms --mode-conf "$CONF" --conf "$CONF"; rc=$?
# on kms now → it fetches from kms at its next start; no kms login yet → say how
if [ $rc = 0 ] && ! ls "${KMS_CREDENTIALS_DIR:-$HERE/credentials}"/*/secret_id >/dev/null 2>&1; then
    echo -e "\033[36m[ INFO ]\033[0m next: sign this component up with kms (once): bash $HERE/signup_with_kms.sh"
fi
exit $rc
