#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_local2tempfile_random_value.sh — mycache (cache-agent): a NEW random value for every key into the temp file — no kms
#                                                  (TESTSERVER-94)
#
# What for    Step 1 of the rotation WITHOUT kms ("local only" deploy): fresh passwords for this component, then
#             cache_config_secret_mgt_local.sh writes them into its config. Instead of cache_transfer_kms2tempfile.sh.
# Who         You — or svcmgt/transfer_all_local2tempfile_random_value.sh (every component; it also says which keys are
#             shared — used by 2+ components — those get ONE value in the shared file, so both sides match).
# How         bash projectspace/mycache/cache-agent/connect_external/kms/cache_transfer_local2tempfile_random_value.sh      (safe to run again)
# Steps       1. the KEY NAMES only, from the "# kms:" comments — the config's values are never read or copied
#             2. a key the file has not yet → 32 random letters/digits; *_API_KEY · *_TOKEN · SMTP_PASS → placeholder-<random>
#                (put your real one in the file) · a key already in the file → kept, never overwritten
# Files       mountspace/temp/myworkspace/projectspace/mycache/cache-agent/secrets.conf  (its own keys · chmod 600 · mirrors the workspace)
#             mountspace/temp/myworkspace/shared/secrets.conf          (keys used by 2+ components, from svcmgt)
# Output      [  OK  ] random → file: 2 new · 0 already there (kept) — …   (values never shown)
# Next        cache_config_secret_mgt_local.sh · remove the plain files later: bash housekeeping/clean_temp.sh (by hand)
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
python3 "$HERE/kms_transfer.py" random2file --mode-conf "$CONF" --conf "$CONF" --own-file "$OWN" --shared-file "$SHARED" --by "mycache (cache-agent)"
