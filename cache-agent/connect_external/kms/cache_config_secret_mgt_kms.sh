#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_config_secret_mgt_kms.sh — mycache (cache-agent): its CONFIG switched to kms — each password line ← the kms address
#                                  from its "# kms:" comment · SECRET_MGT=kms ([1.4.6])
#
# What for    The only script (with cache_config_secret_mgt_local.sh) that writes this component's config. Afterwards it
#             fetches its passwords from kms at start. Send the local values to kms FIRST: cache_transfer_local2kms.sh.
# Who         You — or svcmgt/config_all_secret_mgt_kms.sh (every component).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_config_secret_mgt_kms.sh      (safe to run again)
# Steps       1. kms reachable + a login (master_password file, else asked) → every key must be in kms, else nothing
#                changed ("send them first") · kms not reachable / no login → switched anyway + WARN
#             2. every password line ← the address from its "# kms:" comment · SECRET_MGT=kms
#             3. no kms login for this component yet → how to sign it up (signup_with_kms.sh)
# Output      [  OK  ] config → kms: 2 line(s) back to their kms address — SECRET_MGT=kms (was local); …
# Next        restart the component (it fetches from kms)
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
python3 "$HERE/kms_transfer.py" conf2kms --mode-conf "$CONF" --conf "$CONF"; rc=$?
# on kms now → it fetches from kms at its next start; no kms login yet → say how
if [ $rc = 0 ] && ! ls "${KMS_CREDENTIALS_DIR:-$HERE/credentials}"/*/secret_id >/dev/null 2>&1; then
    echo -e "\033[36m[ INFO ]\033[0m next: sign this component up with kms (once): bash $HERE/signup_with_kms.sh"
fi
exit $rc
