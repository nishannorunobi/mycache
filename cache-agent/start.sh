#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — start the agent's web server (runs INSIDE the container)
#
# Who         host_start.sh — you normally do not run it yourself.
#
# How         (inside the container)  sh /cache-agent/start.sh
#
# Needs       mycache's image (/opt/venv) and the agent's kms login — the secrets are
#             fetched here by connect_external/kms/fetch_from_kms.py (agent.conf = kms addresses)
#
# Errors      kms sealed / not signed up → see the [kms] line; on the host: bash cache-agent/host_start.sh
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

[ -x /opt/venv/bin/python ] || { printf '\033[31m[ERROR]\033[0m /opt/venv missing — this container is not mycache'"'"'s image: bash start.sh on the host\n'; exit 1; }
[ -f "agent.conf" ]         || { printf '\033[31m[ERROR]\033[0m agent.conf not found.\n'; exit 1; }

set -a; . ./agent.conf; set +a      # secret values are kms addresses — fetch_from_kms.py fills them in

PORT="${PORT:-8892}"
LOG_FILE="memory/server.log"
mkdir -p memory

printf '\n\033[1m╔══════════════════════════════════════════╗\033[0m\n'
printf '\033[1m║   Cache Agent                            ║\033[0m\n'
printf '\033[1m╚══════════════════════════════════════════╝\033[0m\n'
printf '  \033[32mAPI:\033[0m  http://localhost:%s\n' "$PORT"
printf '  \033[32mLog:\033[0m  %s\n' "$LOG_FILE"
printf '  Press Ctrl+C to stop.\n\n'

/opt/venv/bin/python connect_external/kms/fetch_from_kms.py /opt/venv/bin/uvicorn server:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --log-level info \
    --access-log \
    --no-use-colors \
    2>&1 | tee -a "$LOG_FILE"
