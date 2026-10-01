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

source .env      # non-secret settings only (version, host, port)

# The password comes from kms over its HTTP API (story KMS [1.4]) — mycache's own client
# connect_external/kms/kms_secrets.sh, no kms file used. Kept in memory, never printed, never a file.
# kms sealed / down → stop here: no fallback to a secret file.
source "$SCRIPT_DIR/connect_external/kms/kms_secrets.sh"
kms_get mycache-redis mycache/redis REDIS_PASSWORD || exit 1

# --no-ui starts the broker only, leaving redis-commander (mycache-redis-ui) down.
# The UI is a convenience, so callers that want a lean start can skip it.
WITH_UI=true
[ "${1:-}" = "--no-ui" ] && WITH_UI=false

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
echo -e "    Password  : ${BOLD}in kms${RESET} (kv/mycache/redis — UI http://127.0.0.1:8110/ui)"
echo -e "    URL       : ${BOLD}redis://:<password>@localhost:${REDIS_PORT}/0${RESET}"
echo ""
echo -e "    ${BOLD}./logs.sh${RESET}    — tail logs"
echo -e "    ${BOLD}./status.sh${RESET}  — container status"
echo -e "    ${BOLD}./stop.sh${RESET}    — stop (data preserved)"
echo -e "    ${BOLD}./destroy.sh${RESET} — stop + wipe all data"
