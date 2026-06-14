#!/bin/sh

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
# health.sh — Quick liveness check for the cache-agent.
curl -sf http://localhost:${PORT:-8892}/health >/dev/null 2>&1 && echo "ok" || echo "down"
