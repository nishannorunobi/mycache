#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — start mycache: the Redis cache (+ web UI on :8081)
#
# What for    Start Redis. The container fetches its own password from kms at start
#             (.env REDIS_PASSWORD = its kms address) — never from a file.
#
# Who         You, or the workspace startup (via ensure_running.sh).
#
# How         bash start.sh             Redis + web UI
#             bash start.sh --no-ui     Redis only
#
# Steps       1. first time only: sign mycache up with kms (asks your kms password)
#             2. docker compose up -d — builds the image once (internet once), then:
#                inside: fetch_from_kms.py → REDIS_PASSWORD from kms → Redis starts
#
# Output      ==> Redis is up
#                 Password  : in kms (kv/mycache/redis)
#
# Errors      kms is SEALED          → unseal kms — the container retries by itself
#                                     (see why: docker logs mycache-redis)
#             not signed up, in startup → run bash start.sh by hand once
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

source .env      # settings; REDIS_PASSWORD is only its kms address

# The container fetches its own secrets (connect_external/kms/fetch_from_kms.py). This PC only
# makes sure mycache has its kms login — once, by hand: it asks your kms password, so never
# inside startup / shutdown (SVC_RUN) and never without a terminal.
if ! ls connect_external/kms/credentials/*/secret_id >/dev/null 2>&1; then
    { [ -z "${SVC_RUN:-}" ] && [ -t 0 ]; } \
        || { echo -e "\033[31m[ERROR]${RESET} mycache is not signed up with kms yet — run by hand once: bash $SCRIPT_DIR/start.sh"; exit 1; }
    bash connect_external/kms/signup_with_kms.sh || exit 1
fi

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
KMS_ENTRY="$(grep -oE '/v1/kv/data/[^ ]+' .env | head -1)"     # where the container reads it (no value)
echo -e "    Password  : ${BOLD}in kms${RESET} (${KMS_ENTRY#/v1/} — fetched by the container)"
echo -e "    URL       : ${BOLD}redis://:<password>@localhost:${REDIS_PORT}/0${RESET}"
echo ""
echo -e "    ${BOLD}./logs.sh${RESET}    — tail logs"
echo -e "    ${BOLD}./status.sh${RESET}  — container status"
echo -e "    ${BOLD}./stop.sh${RESET}    — stop (data preserved)"
echo -e "    ${BOLD}./destroy.sh${RESET} — stop + wipe all data"
