#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_config_secret_mgt_local.sh — mycache (cache-agent): CONFIG SECRET_MGT=local — only that line (TESTSERVER-110)
#
# What for    Switches this component to local: at its next start it uses the plain passwords in its fields, WITHOUT
#             kms. It changes nothing else. Fill the fields first: cache_transfer_tempfile2local.sh.
# Who         You — or svcmgt/config_all_secret_mgt_local.sh (every component; also svc_policy.conf's SECRET_MGT).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_config_secret_mgt_local.sh      (safe to run again)
# Steps       a password field still holding a kms address → refused, nothing changed · else SECRET_MGT=local
# Output      [  OK  ] SECRET_MGT=local (was kms) — runs WITHOUT kms at its next start …
# Next        restart the component · back to kms: cache_transfer_local2kms.sh → _comment2local_kmsurl.sh → _config_secret_mgt_kms.sh
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"                 # REG_*: tests point elsewhere
python3 "$HERE/kms_transfer.py" modelocal --mode-conf "$CONF" --conf "$CONF"
