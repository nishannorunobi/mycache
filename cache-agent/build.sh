#!/bin/sh
# build.sh — Install Python 3, create venv, and install cache-agent dependencies.
# Run INSIDE mycache-redis container (Alpine Linux).
set -eu

# ── Mirror logging ─────────────────────────────────────────────────────────────
_SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
_BASE="$(basename "$_SELF_ABS")"; _EXT="${_BASE##*.}"; _STEM="${_BASE%.*}"
_REL_DIR="$(dirname "${_SELF_ABS#${CONTAINER_WORKDIR:-}/}")"
[ "$_REL_DIR" = "." ] && _REL_DIR="" || _REL_DIR="/$_REL_DIR"
LOG_FILE="${LOG_MIRROR_ROOT:-/tmp/logs}${_REL_DIR}/${_STEM}_${_EXT}.log"
mkdir -p "$(dirname "$LOG_FILE")" && export LOG_FILE
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' | tee -a "$LOG_FILE") 2>&1
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
    printf '\n\033[31m[ACTION REQUIRED]\033[0m Edit agent.conf and set your ANTHROPIC_API_KEY\n'
    printf '  vi agent.conf\n'
else
    success "agent.conf exists."
fi

# ── Create memory directory ───────────────────────────────────────────────────
mkdir -p memory
success "memory/ directory ready."

printf '\n'
success "Build complete. Start the agent with: ./start.sh"
