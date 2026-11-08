#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# credentials_check.sh — mycache's ISSUED credentials: the keys mycache issues (it is the server) — any that need you?
#
# What for    mycache is the server of the Redis password: it issues it, everyone else (Plane, …) only uses it.
#             This runs every *_check.sh in this folder — one per key and kind — and shows ONLY the ones that
#             need you: 🔑 rotation (…_rotation_check.sh) — a password near / past the 90-day rule, a REMINDER,
#             nothing stops · 🎫 expiry (…_expiry_check.sh) — a key the system switches off on a date.
#             A key with time left prints nothing (CONFMGT [8.6]).
# Who         mycache's start.sh and stop.sh (so every workspace startup / shutdown) · you, any time.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/credentials_check.sh
# Steps       1. every *_check.sh beside this file (not itself), in name order, with --quiet (silent while fine)
#             2. their lines as they come · the exit code = the worst one
# Output      [ WARN ] mycache · Redis password: rotate in 5 days (due 2027-01-03 · 90-day rule)
#                      do: bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotate.sh
#             (nothing at all while every key has more than WARN_BEFORE_DAYS left)
# Errors      exit 0 all fine · 1 one needs you soon / is overdue (rotation: a reminder) · 2 one has expired ·
#             3 one could not be read (kms down …) — start.sh / stop.sh never stop because of it
# Next        a new key = a new <key>_rotation_check.sh (+ .py) and <key>_rotate.sh here — found by itself,
#             nothing else changes · keys ANOTHER system gave mycache (it only uses them) go in ../used_credentials/
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging — SILENT on screen: the result always goes to the mirror log, the screen only gets ⚠ / ✗
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
LOG_FILE=/dev/null
if [ -f "$_WS_ROOT/ccc/scripts/lib/create_logging_path.sh" ]; then
    source "$_WS_ROOT/ccc/scripts/lib/create_logging_path.sh"
    LOG_FILE="$(get_mirror_log_path "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")")"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null || LOG_FILE=/dev/null
fi
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"
worst=0; n=0
for c in "$HERE"/*_check.sh; do
    [ -f "$c" ] && [ "$(basename "$c")" != "$SELF" ] || continue
    out="$(bash "$c" --quiet 2>&1)"; rc=$?; n=$((n + 1))
    [ -n "$out" ] && { printf '%s\n' "$out"; while IFS= read -r l; do log "$l"; done <<< "$out"; }
    log "$(basename "$c") → exit $rc"
    [ "$rc" -gt "$worst" ] && worst=$rc
done
log "$n key(s) checked · worst exit $worst"
exit "$worst"
