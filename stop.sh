#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# stop.sh — stop mycache (Redis + web UI); the data is kept
#
# What for    Stop the containers. Cached data stays in the Docker volume.
#
# Who         You, or the workspace shutdown (via ensure_stopped.sh).
#
# How         bash stop.sh
#
# Output      ==> Stopping Redis...
#                 Redis stopped. Data is preserved in Docker volumes.
#
# Note        Plane uses this Redis — it shows errors until mycache runs again.
#
# Next        bash start.sh
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -euo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN="\033[32m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

echo -e "${YELLOW}==> Stopping Redis...${RESET}"
docker compose down
echo -e "${GREEN}    Redis stopped. Data is preserved in Docker volumes.${RESET}"
echo -e "    Run ${BOLD}./start.sh${RESET} to bring it back up."
