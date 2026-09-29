#!/bin/bash
# start.sh — Start the Redis cache.
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

[ -f ".env" ] || { echo -e "\033[31m[ERROR]${RESET} .env not found."; exit 1; }

source .env

# --no-ui starts the broker only, leaving redis-commander (mycache-redis-ui) down.
# The UI is a convenience, so callers that want a lean start can skip it.
WITH_UI=true
[ "${1:-}" = "--no-ui" ] && WITH_UI=false

# Standalone: the shared Docker network this compose joins — created here if missing,
# so the project works without myworkspace (same name and subnet the workspace uses).
docker network inspect my_docker_network >/dev/null 2>&1 \
    || docker network create --subnet=172.28.0.0/16 my_docker_network >/dev/null
running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }
# Idempotent: nothing to do when what was asked for is already up.
if running mycache-redis && { ! $WITH_UI || running mycache-redis-ui; }; then
    echo -e "${GREEN}[  OK  ]${RESET} Redis already running"
    exit 0
fi
echo -e "${BOLD}==> Starting Redis ${REDIS_VERSION}...${RESET}"
if $WITH_UI; then
    docker compose up -d
else
    docker compose up -d redis
    echo -e "${YELLOW}    Redis UI not started (--no-ui).${RESET}"
fi

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
