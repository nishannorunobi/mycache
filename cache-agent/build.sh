#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — install the agent's Python venv (runs INSIDE the container)
#
# Who         host_start.sh, when the venv is missing (the first build needs network).
#
# How         docker exec mycache-redis sh /cache-agent/build.sh
#
# Steps       1. install Python 3 + create .venv
#             2. install requirements.txt
#             3. create agent.conf from the example — no secrets
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

info()    { printf '\033[36m[INFO]\033[0m  %s\n' "$*"; }
success() { printf '\033[32m[ OK ]\033[0m  %s\n' "$*"; }
error()   { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }

# ── Install Python 3 if missing ───────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
    info "Installing Python 3..."
    apk add --no-cache python3 py3-pip
    success "Python 3 installed."
else
    success "Python 3 found: $(python3 --version)"
fi

# ── Create virtual environment ────────────────────────────────────────────────
if [ ! -d ".venv" ]; then
    info "Creating virtual environment..."
    python3 -m venv .venv
    success "venv created."
fi

# ── Install dependencies ──────────────────────────────────────────────────────
info "Installing dependencies..."
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt
success "Dependencies installed."

# ── Create agent.conf if missing ──────────────────────────────────────────────
if [ ! -f "agent.conf" ]; then
    cp agent.conf.example agent.conf
    success "agent.conf created (no secrets — they come from kms at start)."
else
    success "agent.conf exists."
fi

# ── Create memory directory ───────────────────────────────────────────────────
mkdir -p memory
success "memory/ directory ready."

printf '\n'
success "Build complete. Start the agent with: ./start.sh"
