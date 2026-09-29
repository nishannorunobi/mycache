#!/bin/bash
# state.sh — one word for scripts: running / stopped (Redis (mycache), container mycache-redis).
# The human view is still status.sh (unchanged).
#   bash state.sh
set -uo pipefail
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'mycache-redis' && echo running || echo stopped
