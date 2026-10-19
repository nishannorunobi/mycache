#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_tempfile2local.sh — mycache (cache-agent): the temp file → its own config · SECRET_MGT=local (TESTSERVER-85/94)
#
# What for    Step 2 of the rotation: the component runs on plain passwords WITHOUT kms ("local deploy"). The file
#             comes from cache_transfer_kms2tempfile.sh (kms's values) or cache_transfer_local2tempfile_random_value.sh
#             (new random ones). Back to kms later: cache_transfer_local2kms.sh.
# Who         You — or svcmgt/transfer_all_tempfile2local.sh (every component).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_transfer_tempfile2local.sh      (safe to run again: the same → not written)
# Steps       1. each password line (its "# kms:" comment names the key) ← its value from its own file, else the shared file
#             2. the "# kms:" comment kept (added when missing) — the kms address is never lost · SECRET_MGT=local
#             3. a key in neither file: its line keeps its local value (WARN) — but a line that would keep a kms address
#                → nothing changed at all (fill the file first)
# Output      [  OK  ] file → local: 2 written · 0 the same · 0 not in the file — SECRET_MGT=local (was kms); runs WITHOUT kms …
# Errors      no file at all → "make one first", nothing changed
# Next        restart the component (it runs without kms) · remove the plain files: bash housekeeping/clean_temp.sh (by hand)
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
