#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_config_secret_mgt_local.sh — mycache (cache-agent): its CONFIG switched to local — each password line ← its value from
#                                    the temp file · SECRET_MGT=local (TESTSERVER-102)
#
# What for    The only script (with cache_config_secret_mgt_kms.sh) that writes this component's config. Afterwards it
#             runs on plain passwords WITHOUT kms ("local deploy"). The temp file comes from a transfer script:
#             cache_transfer_kms2tempfile.sh (kms's values) or cache_transfer_local2tempfile_random_value.sh (new random).
# Who         You — or svcmgt/config_all_secret_mgt_local.sh (every component).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_config_secret_mgt_local.sh      (safe to run again)
# Steps       1. every password line under its "# kms:" comment ← its value from the own temp file, else the shared one
#             2. SECRET_MGT=local — the "# kms:" comments stay, so cache_config_secret_mgt_kms.sh can switch back
#             ALL OR NOTHING: a key not in the temp file · a kms address without its "# kms:" comment → nothing changed
# Output      [  OK  ] config → local: 2 written · 0 the same — SECRET_MGT=local (was kms); runs WITHOUT kms now …
# Next        restart the component · remove the plain files: bash housekeeping/clean_temp.sh (by hand)
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
