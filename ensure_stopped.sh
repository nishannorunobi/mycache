#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ensure_stopped.sh — stop mycache only if it runs
#
# What for    Safe to run any number of times.
#
# Who         The workspace shutdown (svcmgt).
#
# How         bash ensure_stopped.sh
#
# Steps       1. running → stop.sh
#             2. otherwise → "already stopped"
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^mycache-redis(-ui)?$'; then
    echo -e "\033[32m[  OK  ]\033[0m Redis (mycache) already stopped"; exit 0
fi
bash "$SCRIPT_DIR/stop.sh" "$@"
