#!/bin/bash
# host_stop.sh — stop the cache-agent (Cache agent) inside mycache-redis, from the HOST.
# Idempotent: nothing to do when the container or the agent is not running. Standalone
# (moved here from agents/docker-manager-agent/cacheagent/stop-cache-agent.sh, 2026-09-29).
#   bash host_stop.sh
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

if ! curl -fsS --max-time 3 -o /dev/null "http://localhost:8892/health" 2>/dev/null \
   && ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx mycache-redis; then
    echo "[OK] Cache agent already stopped"
    exit 0
fi

CONTAINER="mycache-redis"

if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "[WARN] Container $CONTAINER is not running — nothing to stop."
    exit 0
fi

docker exec "$CONTAINER" sh -c \
    "pkill -f '[u]vicorn server:app' 2>/dev/null \
     && echo '[OK] Cache agent stopped.' \
     || echo '[WARN] No running cache-agent found.'"

# Wait until it no longer answers (it can serve a moment after the signal) — so an
# immediate start does not mistake a dying agent for a running one.
for _ in $(seq 1 15); do
    curl -fsS --max-time 1 -o /dev/null "http://localhost:8892/health" 2>/dev/null || exit 0
    sleep 1
done
echo "[WARN] still answering on :8892 after stop"
