#!/bin/bash
# start.sh — Start the Redis cache.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN="\033[32m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

[ -f ".env" ] || { echo -e "\033[31m[ERROR]${RESET} .env not found."; exit 1; }

source .env

echo -e "${BOLD}==> Starting Redis ${REDIS_VERSION}...${RESET}"
docker compose up -d

echo ""
echo -e "${GREEN}${BOLD}==> Redis is up${RESET}"
echo -e "    Host      : ${BOLD}${REDIS_HOST}:${REDIS_PORT}${RESET}"
echo -e "    Password  : ${BOLD}${REDIS_PASSWORD}${RESET}"
echo -e "    URL       : ${BOLD}redis://:${REDIS_PASSWORD}@localhost:${REDIS_PORT}/0${RESET}"
echo ""
echo -e "    ${BOLD}./logs.sh${RESET}    — tail logs"
echo -e "    ${BOLD}./status.sh${RESET}  — container status"
echo -e "    ${BOLD}./stop.sh${RESET}    — stop (data preserved)"
echo -e "    ${BOLD}./destroy.sh${RESET} — stop + wipe all data"
