#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — (inside the container) the cache-agent is already running: it is the entry point
#
# What for    Older callers (the Docker dashboard) run this to start the agent. The agent
#             now starts with the container (supervisor.py), so this only reports.
#
# Who         The Docker dashboard, or you inside the container.
#
# How         sh /cache-agent/start.sh
#
# Output      [OK] cache-agent is running on :8892 (started by supervisor.py)
#
# Errors      not answering → the supervisor restarts it by itself; reason: docker logs mycache-redis
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -eu

# ── Mirror logging — POSIX sh: no BASH_SOURCE, no process substitution ────────
_SELF_ABS="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
_BASE="$(basename "$_SELF_ABS")"; _EXT="${_BASE##*.}"; _STEM="${_BASE%.*}"
_REL_DIR="$(dirname "${_SELF_ABS#${CONTAINER_WORKDIR:-}/}")"
[ "$_REL_DIR" = "." ] && _REL_DIR="" || _REL_DIR="/$_REL_DIR"
LOG_FILE="${LOG_MIRROR_ROOT:-/tmp/logs}${_REL_DIR}/${_STEM}_${_EXT}.log"
mkdir -p "$(dirname "$LOG_FILE")" && export LOG_FILE
# POSIX sh has no process substitution (`> >(...)`), so route stdout/stderr through
# a FIFO instead: start the timestamper reading it in the background, then point this
# script's output at it. Same result as the bash block, no bashisms. The FIFO is
# unlinked immediately — the open descriptors keep working, nothing is left in /tmp.
_LOG_FIFO="/tmp/.mirrorlog.$$"
if mkfifo "$_LOG_FIFO" 2>/dev/null; then
    awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' < "$_LOG_FIFO" | tee -a "$LOG_FILE" &
    exec > "$_LOG_FIFO" 2>&1
    rm -f "$_LOG_FIFO"
else
    exec >> "$LOG_FILE" 2>&1      # last resort: append untimestamped rather than lose the log
fi
echo "[logging] → $LOG_FILE"
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
PORT="$(grep -E '^PORT=' agent.conf | cut -d= -f2 | tr -d ' ')"; PORT="${PORT:-8892}"
if wget -q -O /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; then
    printf '\033[32m[  OK  ]\033[0m cache-agent is running on :%s (started by supervisor.py, the container entry point)\n' "$PORT"
    exit 0
fi
printf '\033[33m[WARN]\033[0m   cache-agent is not answering on :%s — supervisor.py restarts it by itself; reason: docker logs mycache-redis\n' "$PORT"
exit 1
