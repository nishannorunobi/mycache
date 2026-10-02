#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — start mycache: the Redis cache (+ web UI on :8081)
#
# What for    Start Redis. Its password comes from kms — never from a file.
#
# Who         You, or the workspace startup (via ensure_running.sh).
#
# How         bash start.sh             Redis + web UI
#             bash start.sh --no-ui     Redis only
#
# Steps       1. read .env — plain settings: version, port, KMS_URL
#             2. get REDIS_PASSWORD from kms — in memory, never printed
#             3. docker compose up -d — password → container env → /run (RAM)
#
# Output      ==> Redis is up
#                 Password  : in kms (kv/mycache/redis)
#
# Errors      kms is SEALED          → unseal kms, run again
#             no kms login files     → bash connect_external/kms/signup_with_kms.sh
#
# Next        bash status.sh  ·  bash stop.sh
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -euo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN="\033[32m"; YELLOW="\033[33m"; BOLD="\033[1m"; RESET="\033[0m"

[ -f ".env" ] || { echo -e "\033[31m[ERROR]${RESET} .env not found."; exit 1; }

source .env      # non-secret settings only: version, host, port, KMS_URL, KMS_APPROLE_DIR

# The password comes from kms over its HTTP API (story KMS [1.4]) — mycache's own client
# connect_external/kms/fetch_from_kms.sh, no kms file used. Kept in memory, never printed, never a file.
# kms sealed / down → stop here: no fallback to a secret file.
source "$SCRIPT_DIR/connect_external/kms/fetch_from_kms.sh"
kms_get mycache-redis mycache/redis REDIS_PASSWORD || exit 1

# --no-ui starts the broker only, leaving redis-commander (mycache-redis-ui) down.
# The UI is a convenience, so callers that want a lean start can skip it.
WITH_UI=true
[ "${1:-}" = "--no-ui" ] && WITH_UI=false

echo -e "${BOLD}==> Starting Redis ${REDIS_VERSION}...${RESET}"
if $WITH_UI; then
    docker compose up -d
else
    docker compose up -d redis
    echo -e "${YELLOW}    Redis UI not started (--no-ui).${RESET}"
fi

echo ""
echo -e "${GREEN}${BOLD}==> Redis is up${RESET}"
echo -e "    Host      : ${BOLD}${REDIS_HOST}:${REDIS_PORT}${RESET}"
echo -e "    Password  : ${BOLD}in kms${RESET} (kv/mycache/redis — UI http://127.0.0.1:8110/ui)"
echo -e "    URL       : ${BOLD}redis://:<password>@localhost:${REDIS_PORT}/0${RESET}"
echo ""
echo -e "    ${BOLD}./logs.sh${RESET}    — tail logs"
echo -e "    ${BOLD}./status.sh${RESET}  — container status"
echo -e "    ${BOLD}./stop.sh${RESET}    — stop (data preserved)"
echo -e "    ${BOLD}./destroy.sh${RESET} — stop + wipe all data"
