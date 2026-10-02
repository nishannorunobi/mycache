#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_start.sh — start the cache-agent (AI helper, :8892) from the host
#
# What for    Run the agent inside the mycache-redis container.
#
# Who         You (it is not started by default).
#
# How         bash cache-agent/host_start.sh
#
# Steps       1. already answering on :8892 → nothing to do
#             2. get ANTHROPIC_API_KEY + REDIS_PASSWORD from kms (the agent's own login)
#             3. build the venv if missing
#             4. start it: docker exec -e … — values by name, never on a command line
#
# Output      [OK] Cache agent running on :8892
#
# Errors      kms is SEALED          → unseal kms, run again
#             no kms login files     → bash cache-agent/connect_external/kms/register_to_kms.sh
#             container not running   → bash start.sh
#
# Next        bash cache-agent/host_status.sh  ·  bash cache-agent/host_stop.sh
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
AGENT_DIR="/cache-agent"

# The agent's secrets come from kms over its HTTP API (story KMS [1.4]) — the agent's OWN client
# connect_external/kms/kms_secrets.sh and its own login (mycache-cache-agent); no file of kms or of
# the Redis server is used. In memory only, handed to the agent by NAME (docker exec -e …): the
# values never appear on a command line. kms sealed / down → stop here.
# where kms is: the agent's own settings (only the KMS_* lines of agent.conf)
[ -f "$SCRIPT_DIR/agent.conf" ] && source <(grep -E '^KMS_(URL|APPROLE_DIR)=' "$SCRIPT_DIR/agent.conf")
source "$SCRIPT_DIR/connect_external/kms/kms_secrets.sh"
kms_get mycache-cache-agent shared/anthropic ANTHROPIC_API_KEY || exit 1
kms_get mycache-cache-agent mycache/redis REDIS_PASSWORD || exit 1

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
docker exec -e ANTHROPIC_API_KEY -e REDIS_PASSWORD "$CONTAINER" sh -c \
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
