#!/bin/bash
# ensure_running.sh — start Redis only if it is not up: calls the project's own start.sh
# (unchanged; same arguments, e.g. --no-ui) when needed, then checks it really runs.
# Safe to run any number of times. Standalone.
#   bash ensure_running.sh [--no-ui]
set -uo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
err()  { echo -e "\033[31m[ERROR]\033[0m  $*"; }
running() { docker ps --format "{{.Names}}" 2>/dev/null | grep -qx "$1"; }
WITH_UI=true; [ "${1:-}" = --no-ui ] && WITH_UI=false
if running mycache-redis && { ! $WITH_UI || running mycache-redis-ui; }; then ok "Redis already running"; exit 0; fi
# Standalone: the shared Docker network this compose joins — created if missing, so the
# project works without myworkspace (same name and subnet the workspace uses).
docker network inspect my_docker_network >/dev/null 2>&1 \
    || docker network create --subnet=172.28.0.0/16 my_docker_network >/dev/null
bash "$SCRIPT_DIR/start.sh" "$@" || { err "start.sh failed"; exit 1; }
running mycache-redis && ok "Redis running" || { err "Redis container is not running after start.sh"; exit 1; }
