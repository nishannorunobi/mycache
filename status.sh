#!/bin/bash
# status.sh — Show running status for the Redis cache container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD="\033[1m"; RESET="\033[0m"

echo -e "${BOLD}==> Redis container status${RESET}"
docker compose ps
