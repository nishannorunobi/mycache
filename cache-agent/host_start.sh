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

# The Anthropic key comes from kms (story KMS [1.4]) — in memory only, handed to the agent by
# NAME (docker exec -e ANTHROPIC_API_KEY): the value never appears on a command line.
# REDIS_PASSWORD is already in the container's environment. kms sealed / down → stop here.
KMS_FETCH="$SCRIPT_DIR/../../kms/lib/kms_fetch.sh"
[ -f "$KMS_FETCH" ] || { echo "[ERROR] kms not found ($KMS_FETCH) — clone projectspace/kms" >&2; exit 1; }
source "$KMS_FETCH"
kms_fetch mycache-cache-agent shared/anthropic ANTHROPIC_API_KEY || exit 1

if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "[ERROR] Container $CONTAINER is not running." >&2
    exit 1
fi

# Build venv if missing, Python broken, or uvicorn not installed (Alpine: sh not bash)
# "venv exists" is not "venv works": run it. A .venv whose python is missing in this
# container ("uvicorn: not found") is rebuilt (build.sh — the first build needs network).
if ! docker exec "$CONTAINER" sh -c "$AGENT_DIR/.venv/bin/python -c 'import uvicorn'" &>/dev/null; then
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
docker exec -e ANTHROPIC_API_KEY "$CONTAINER" sh -c \
    "cd $AGENT_DIR && . ./agent.conf && \
     .venv/bin/uvicorn server:app \
        --host 0.0.0.0 --port \${PORT:-8892} \
        --no-use-colors --access-log" \
    < /dev/null 2>&1 \
    | awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$LOG_FILE" 2>/dev/null &   # file only: never hold the caller's output pipe
disown

# Say OK only when the agent really answers — the launch above returns at once even if
# uvicorn dies a second later (e.g. a broken .venv: "uvicorn: not found").
for _ in $(seq 1 30); do
    curl -fsS --max-time 2 -o /dev/null "http://localhost:8892/health" 2>/dev/null && { echo "[OK] Cache agent running on :8892"; exit 0; }
    sleep 1
done
echo "[ERROR] Cache agent did not come up on :8892 — its output:"
tail -5 "$LOG_FILE" 2>/dev/null | sed -E 's/^(\[[0-9-]+ [0-9:]+\] )+/    /'
exit 1
