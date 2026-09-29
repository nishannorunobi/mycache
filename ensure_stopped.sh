#!/bin/bash
# ensure_stopped.sh — stop Redis (mycache) only if it runs: calls the project's own stop.sh
# (unchanged) when a container of it is up, otherwise says "already stopped". Safe to
# run any number of times. Standalone.
#   bash ensure_stopped.sh
set -uo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^mycache-redis(-ui)?$'; then
    echo -e "\033[32m[  OK  ]\033[0m Redis (mycache) already stopped"; exit 0
fi
bash "$SCRIPT_DIR/stop.sh" "$@"
