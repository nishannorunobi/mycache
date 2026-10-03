#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_start.sh — make sure the cache-agent (Redis's assistant, :8892) is running
#
# What for    The agent is the mycache container's entry point: it starts with Redis and
#             stays on. So "start the agent" = make sure the container runs.
#
# Who         You, or the workspace startup (svcmgt).
#
# How         bash cache-agent/host_start.sh
#
# Steps       1. already answering on :8892 → nothing to do
#             2. container not running → bash ../start.sh (signs the agent up once, by hand)
#             3. wait until :8892 answers (the supervisor restarts the API by itself)
#
# Output      [OK] Cache agent running on :8892
#
# Errors      container up but no answer → docker logs mycache-redis ([agent] lines say why:
#                                          kms sealed / not signed up / key missing)
#
# Next        bash cache-agent/host_status.sh  ·  stop = bash stop.sh (Redis and agent together)
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

if curl -fsS --max-time 3 -o /dev/null "http://localhost:8892/health" 2>/dev/null; then
    echo "[OK] Cache agent already running on :8892"
    exit 0
fi

CONTAINER="mycache-redis"
if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "[INFO] $CONTAINER is not running — starting mycache (the agent is its entry point)"
    bash "$SCRIPT_DIR/../start.sh" --no-ui || exit 1
fi

# The supervisor inside starts the API and restarts it if it dies — only wait for it.
for _ in $(seq 1 30); do
    curl -fsS --max-time 2 -o /dev/null "http://localhost:8892/health" 2>/dev/null && { echo "[OK] Cache agent running on :8892"; exit 0; }
    sleep 1
done
echo "[ERROR] the cache-agent does not answer on :8892 — why: docker logs --tail 20 $CONTAINER" >&2
docker logs --tail 5 "$CONTAINER" 2>&1 | grep '\[agent\]' >&2 || true
exit 1
