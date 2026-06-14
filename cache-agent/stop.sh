#!/bin/sh
# stop.sh — Stop the running cache-agent process inside the container.
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

if pkill -f '[u]vicorn server:app' 2>/dev/null; then
    printf '\033[32m[ OK ]\033[0m  Cache agent stopped.\n'
else
    printf '\033[33m[WARN]\033[0m  No running cache-agent server found.\n'
fi
