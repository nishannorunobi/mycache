#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — start mycache: the Redis cache (+ web UI on :8081)
#
# What for    Start Redis. The cache-agent is the container's entry point: it gets the
#             password from kms (cache-agent/agent.conf = kms addresses), starts Redis
#             and serves its API on :8892 — never a password from a file.
#
# Who         You, or the workspace startup (via ensure_running.sh).
#
# How         bash start.sh             Redis + web UI
#             bash start.sh --no-ui     Redis only
#
# Steps       1. first time only: the cache-agent signs itself up with kms as it starts (your kms password from
#                kms's master_password, .env KMS_MASTER_PASSWORD_DIR) — file empty → asks here, by hand only
#             2. docker compose up -d — builds the image once (internet once), then:
#                inside: cache-agent/supervisor.py → kms → Redis + the agent API
#
# Output      ==> Redis is up
#                 Password  : in kms (kv/mycache/redis)
#
# Errors      kms is SEALED          → unseal kms — the container retries by itself
#                                     (see why: docker logs mycache-redis)
#             not signed up, master_password empty → put your kms password there, or run bash start.sh by hand once
#             the agent / Redis failed  → docker logs mycache-redis ([agent] lines say why)
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

source .env      # Redis settings — no secret

# The cache-agent fetches the secrets inside the container (its connect_external/kms/) — and signs itself up with
# kms when it has no login yet (TESTSERVER-24): with the owner's kms password from kms's master_password folder
# (.env KMS_MASTER_PASSWORD_DIR), mounted read-only. Before the start, this script only checks that the agent CAN
# sign up — else the container would stop and be restarted again and again. Started by hand in a terminal with the
# file empty → it signs up here and asks your kms password (as before).
MASTER_PW_DIR="${KMS_MASTER_PASSWORD_DIR:-}"
[ -n "$MASTER_PW_DIR" ] && [ "${MASTER_PW_DIR#/}" = "$MASTER_PW_DIR" ] && MASTER_PW_DIR="$SCRIPT_DIR/$MASTER_PW_DIR"
MASTER_PW="$MASTER_PW_DIR/master_password"
if ! ls cache-agent/connect_external/kms/credentials/*/secret_id >/dev/null 2>&1; then
    if [ -n "$MASTER_PW_DIR" ] && [ -s "$MASTER_PW" ] && grep -q '[^[:space:]]' "$MASTER_PW" 2>/dev/null; then
        echo -e "\033[36m[ INFO ]${RESET} the cache-agent has no kms login yet — it signs itself up as it starts (kms's master_password is filled)"
    elif [ -z "${SVC_RUN:-}" ] && [ -t 0 ]; then
        bash cache-agent/connect_external/kms/signup_with_kms.sh || exit 1
    else
        echo -e "\033[31m[ERROR]${RESET} the cache-agent is not signed up with kms yet — put your kms password into $MASTER_PW (kms's master_password), then start again — or once by hand: bash $SCRIPT_DIR/start.sh"; exit 1
    fi
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
KMS_ENTRY="$(grep -E '^REDIS_PASSWORD=' cache-agent/agent.conf | grep -oE '/v1/kv/data/[^ ]+' | head -1)"   # where (no value)
echo -e "    Password  : ${BOLD}in kms${RESET} (${KMS_ENTRY#/v1/} — fetched by the cache-agent)"
echo -e "    Agent     : ${BOLD}http://localhost:8892${RESET} (Redis's assistant — always on)"
echo -e "    URL       : ${BOLD}redis://:<password>@localhost:${REDIS_PORT}/0${RESET}"
echo ""
echo -e "    ${BOLD}./logs.sh${RESET}    — tail logs"
echo -e "    ${BOLD}./status.sh${RESET}  — container status"
echo -e "    ${BOLD}./stop.sh${RESET}    — stop (data preserved)"
echo -e "    ${BOLD}./destroy.sh${RESET} — stop + wipe all data"
