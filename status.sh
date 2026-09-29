#!/bin/bash

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────
# status.sh — Show running status for the Redis cache container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# status.sh --state → one word for scripts: running / stopped
if [ "${1:-}" = --state ]; then
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'mycache-redis' && echo running || echo stopped
    exit 0
fi
BOLD="\033[1m"; RESET="\033[0m"

echo -e "${BOLD}==> Redis container status${RESET}"
docker compose ps
