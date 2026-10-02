#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_stop.sh — stop the cache-agent, from the host
#
# Who         You.
#
# How         bash cache-agent/host_stop.sh
#
# Note        Nothing to do if the agent or the container is not running.
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

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
