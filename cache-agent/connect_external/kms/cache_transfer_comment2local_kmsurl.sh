#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_comment2local_kmsurl.sh — mycache (cache-agent): TRANSFER the "# kms:" comments → the password fields (each ←
#                                          its kms address) (TESTSERVER-110)
#
# What for    Reads the "# kms:" comments, writes this component's password fields — nothing else: SECRET_MGT is NOT
#             touched (that is cache_config_secret_mgt_kms.sh, next). Send the plain values to kms BEFORE, they are gone
#             from the fields after this: cache_transfer_local2kms.sh.
# Who         You — or svcmgt/transfer_all_comment2local_kmsurl.sh (every component).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_transfer_comment2local_kmsurl.sh      (safe to run again; no kms needed)
# Output      [  OK  ] comments → password fields: 2 back to their kms address · 0 already — SECRET_MGT not touched …
# Next        cache_config_secret_mgt_kms.sh
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"                 # REG_*: tests point elsewhere
python3 "$HERE/kms_transfer.py" comment2local --mode-conf "$CONF" --conf "$CONF"
