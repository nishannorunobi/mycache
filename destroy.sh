#!/bin/bash
# destroy.sh — Stop Redis AND delete all data volumes (full reset).
# WARNING: This permanently deletes all cached data.
set -euo pipefail

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
