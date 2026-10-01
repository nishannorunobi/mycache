#!/bin/sh
# start.sh — Start the Cache Agent HTTP server inside mycache-redis container.
# Run INSIDE the container. Starts uvicorn on PORT (default 8892).
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

[ -d ".venv" ]      || { printf '\033[31m[ERROR]\033[0m .venv not found. Run ./build.sh first.\n'; exit 1; }
[ -f "agent.conf" ] || { printf '\033[31m[ERROR]\033[0m agent.conf not found. Run ./build.sh first.\n'; exit 1; }

. ./agent.conf
[ -n "${ANTHROPIC_API_KEY:-}" ] || { printf '\033[31m[ERROR]\033[0m ANTHROPIC_API_KEY not set — start the agent from the host: bash host_start.sh (it fetches the key from kms)\n'; exit 1; }

PORT="${PORT:-8892}"
LOG_FILE="memory/server.log"
mkdir -p memory

printf '\n\033[1m╔══════════════════════════════════════════╗\033[0m\n'
printf '\033[1m║   Cache Agent                            ║\033[0m\n'
printf '\033[1m╚══════════════════════════════════════════╝\033[0m\n'
printf '  \033[32mAPI:\033[0m  http://localhost:%s\n' "$PORT"
printf '  \033[32mLog:\033[0m  %s\n' "$LOG_FILE"
printf '  Press Ctrl+C to stop.\n\n'

.venv/bin/uvicorn server:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --log-level info \
    --access-log \
    --no-use-colors \
    2>&1 | tee -a "$LOG_FILE"
