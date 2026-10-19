#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_export_secrets_kms2file.sh — mycache (cache-agent): every password read from kms into a PLAIN hand-over file (TESTSERVER-85)
#
# What for    A plain copy of this component's passwords, to fill its config later WITHOUT kms
#             (cache_readfile_write2conf.sh, when SECRET_MGT=local). The config itself is NOT changed.
# Who         You — or svcmgt/export_all_secrets_kms2file.sh (every component, one kms login; it also says which keys
#             are shared — used by 2+ components — and those go to the shared file).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_export_secrets_kms2file.sh      (safe to run again: rewrites the file)
# Login       kms's master_password file · not there → asks your kms password in the terminal · no terminal → one line, stop
# Files       mountspace/temp/myworkspace/projectspace/mycache/cache-agent/secrets.conf  (its own keys · chmod 600 · mirrors the workspace)
#             mountspace/temp/myworkspace/shared/secrets.conf          (keys used by 2+ components, from svcmgt)
#             one line per kms key: <entry>#<KEY>=<value>, "used by" above it · a key kms lacks → NOT_FOUND_IN_KMS
# Output      [  OK  ] kms → file: 2 in its own file · 0 in the shared file · 0 not found in kms — …   (values never shown)
# Errors      kms not running · login refused · a read refused → one line, nothing written
# Next        remove the plain files when done: bash housekeeping/clean_temp.sh (by hand)
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"                 # REG_*: tests point elsewhere
COMP="$(cd "$HERE/../.." && pwd)"                                    # this component's folder
# the hand-over files mirror the workspace under mountspace/temp (TESTSERVER-85); SECRETS_*: svcmgt / tests hand them over
_TMPWS="${SECRETS_TEMP_DIR:-$_WS_ROOT/mountspace/temp}/$(basename "$_WS_ROOT")"
OWN="${SECRETS_OWN_FILE:-$_TMPWS/${COMP#$_WS_ROOT/}/secrets.conf}"
SHARED="${SECRETS_SHARED_FILE:-$_TMPWS/shared/secrets.conf}"
export KMS_MASTER_PASSWORD_FILE="${KMS_MASTER_PASSWORD_FILE:-$_WS_ROOT/mountspace/usb/myworkspace/projectspace/kms/master_password/master_password}"
python3 "$HERE/kms_transfer.py" kms2file --mode-conf "$CONF" --conf "$CONF" --own-file "$OWN" --shared-file "$SHARED" --by "mycache (cache-agent)"
