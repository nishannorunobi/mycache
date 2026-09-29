#!/bin/bash
# host_start.sh — start the cache-agent (Cache agent, :8892) INSIDE mycache-redis, from the HOST.
# Part of the cache-agent project (this folder); its own start.sh runs inside the container.
# Idempotent: when the agent already answers on :8892, nothing is done. Standalone —
# no workspace paths (moved here from agents/docker-manager-agent/cacheagent/start-cache-agent.sh, 2026-09-29).
#   bash host_start.sh
set -euo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    LOG_FILE="$(get_mirror_log_path "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")")"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    # This agent's own log folder is written by its container (root-owned) — then log
    # right next to it instead: …/<project>/<agent>_<script>_sh.log
    if [ ! -w "$(dirname "$LOG_FILE")" ]; then
        LOG_FILE="$(dirname "$(dirname "$LOG_FILE")")/$(basename "$(dirname "$LOG_FILE")")_$(basename "$LOG_FILE")"
    fi
    exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' | tee -a "$LOG_FILE") 2>&1
    export LOG_FILE
    echo "[logging] → $LOG_FILE"
fi
# ──────────────────────────────────────────────────────────────────────────────
# Standalone (no workspace → no mirror log): keep the agent's output next to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/memory/host_start.log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if curl -fsS --max-time 3 -o /dev/null "http://localhost:8892/health" 2>/dev/null; then
    echo "[OK] Cache agent already running on :8892"
    exit 0
fi

CONTAINER="mycache-redis"
AGENT_DIR="/cache-agent"

if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "[ERROR] Container $CONTAINER is not running." >&2
    exit 1
fi

# Build venv if missing, Python broken, or uvicorn not installed (Alpine: sh not bash)
if ! docker exec "$CONTAINER" sh -c "test -f $AGENT_DIR/.venv/bin/uvicorn" &>/dev/null; then
    echo "[INFO] Building cache-agent venv inside container..."
    docker exec "$CONTAINER" rm -rf "$AGENT_DIR/.venv"
    docker exec "$CONTAINER" sh "$AGENT_DIR/build.sh"
fi

# Kill any existing cache-agent uvicorn (idempotent).
# The [u]vicorn bracket trick prevents pkill from matching its own command line.
docker exec "$CONTAINER" sh -c \
    "pkill -f '[u]vicorn server:app' 2>/dev/null; sleep 0.3; echo ok"

# Start fresh; route logs to mountspace on the host via nohup+disown.
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" 2>/dev/null || true   # create if possible; never abort
docker exec "$CONTAINER" sh -c \
    "cd $AGENT_DIR && . ./agent.conf && \
     .venv/bin/uvicorn server:app \
        --host 0.0.0.0 --port \${PORT:-8892} \
        --no-use-colors --access-log" \
    < /dev/null 2>&1 \
    | awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$LOG_FILE" &
disown

echo "[OK] Cache agent started inside $CONTAINER."
