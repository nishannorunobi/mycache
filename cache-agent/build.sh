#!/bin/sh
# build.sh — Install Python 3, create venv, and install cache-agent dependencies.
# Run INSIDE mycache-redis container (Alpine Linux).
set -eu

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
