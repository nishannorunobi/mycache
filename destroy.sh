#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — ⚠ stop mycache AND delete all its data (full reset)
#
# What for    Start over with an empty cache. The data is gone for good.
#
# Who         You only, on purpose.
#
# How         bash destroy.sh
#
# Steps       1. asks you to confirm
#             2. docker compose down -v — containers + data volume removed
#
# Note        Plane loses its cache (it rebuilds it). Secrets in kms are not touched.
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

RED="\033[31m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

echo -e "${RED}${BOLD}WARNING: This will permanently delete all Redis data.${RESET}"
read -r -p "Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo -e "${YELLOW}==> Stopping and removing Redis containers + volumes...${RESET}"
docker compose down -v --remove-orphans
echo -e "${RED}    All Redis data deleted.${RESET}"
echo -e "    Run ${BOLD}./start.sh${RESET} to start fresh."
