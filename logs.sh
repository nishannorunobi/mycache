#!/bin/bash

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────
# logs.sh — Tail logs for the Redis cache container.
# Usage:
#   ./logs.sh   → tail all logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker compose logs -f --tail=100
