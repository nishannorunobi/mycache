#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_readfile_write2conf.sh — mycache (cache-agent): the plain hand-over file → its own config, ONLY when SECRET_MGT=local (TESTSERVER-85)
#
# What for    Fill this component's local config from the file cache_export_secrets_kms2file.sh wrote — no kms needed.
#             SECRET_MGT=kms → skipped (a kms config holds kms addresses, never plain passwords).
# Who         You — or svcmgt/readfile_write2conf.sh (every component).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_readfile_write2conf.sh      (safe to run again: the same → not written)
# Steps       1. SECRET_MGT not local → "skipped", nothing changed
#             2. each password line (its "# kms:" comment names the key) ← the value from its own file, else the shared file
#             3. a key in neither file / NOT_FOUND_IN_KMS → the line left as it is (WARN)
# Output      [  OK  ] file → config: 2 written · 0 the same · 0 not in the file — SECRET_MGT=local   (values never shown)
# Errors      no secrets file at all → "run the export first", nothing changed
# Next        remove the plain files when done: bash housekeeping/clean_temp.sh (by hand) · restart the component
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
python3 "$HERE/kms_transfer.py" file2conf --mode-conf "$CONF" --conf "$CONF" --own-file "$OWN" --shared-file "$SHARED" --by "mycache (cache-agent)"
