#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_local2kms.sh — mycache (cache-agent): every plain password in agent.conf sent to kms —
#                                 the config NOT changed (TESTSERVER-75 · TESTSERVER-102)
#
# What for    TRANSFER — reads this component's config (its plain password lines), writes kms; the config is NOT
#             changed. Then switch the config: cache_config_secret_mgt_kms.sh.
#             Each line under its "# kms: <address>" comment: the key missing in kms → added · there but
#             different → kms updated (a new version) · the same → left · empty / NOT_FOUND_IN_KMS → not sent
# Who         You — or svcmgt/transfer_all_local2kms.sh (every component, one kms login).
# How         bash cache-agent/connect_external/kms/cache_transfer_local2kms.sh      (asks your kms password; safe to run again)
# Steps       1. SECRET_MGT=kms (its lines hold addresses) → nothing to send
#             2. owner login (master_password file, else asked) · each value → kms, one write per entry, other keys kept
# Output      [  OK  ] local → kms: 0 added · 1 updated · 1 the same · 0 not sent — agent.conf NOT changed …
# Errors      kms not running · login refused · a write refused → one line, the config unchanged
# Next        cache_config_secret_mgt_kms.sh (switches the config to kms)
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
exit $rc
