#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# health.sh — print ok / down: is the agent answering? (inside the container)
#
# Who         Scripts.
#
# How         (inside the container)  sh /cache-agent/health.sh
#
# Output      ok
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

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
curl -sf http://localhost:${PORT:-8892}/health >/dev/null 2>&1 && echo "ok" || echo "down"
