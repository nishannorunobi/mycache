#!/bin/sh

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
# health.sh — Quick liveness check for the cache-agent.
curl -sf http://localhost:${PORT:-8892}/health >/dev/null 2>&1 && echo "ok" || echo "down"
