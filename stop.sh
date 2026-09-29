#!/bin/bash
# stop.sh — Stop Redis (data is preserved in Docker volumes).
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

# Idempotent: nothing to stop when no container of this project runs.
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'mycache-redis\|mycache-redis-ui'; then
    echo -e "${GREEN}[  OK  ]${RESET} Redis already stopped"
    exit 0
fi
echo -e "${YELLOW}==> Stopping Redis...${RESET}"
docker compose down
echo -e "${GREEN}    Redis stopped. Data is preserved in Docker volumes.${RESET}"
echo -e "    Run ${BOLD}./start.sh${RESET} to bring it back up."
