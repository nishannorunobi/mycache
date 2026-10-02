#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ensure_running.sh — start mycache only if it is not running
#
# What for    Safe to run any number of times.
#
# Who         The workspace startup (svcmgt).
#
# How         bash ensure_running.sh [--no-ui]
#
# Steps       1. running already → says so
#             2. otherwise → start.sh (same arguments), then checks it runs
#
# Output      [  OK  ] Redis running
#
# Errors      the same as start.sh (e.g. kms sealed)
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
err()  { echo -e "\033[31m[ERROR]\033[0m  $*"; }
running() { docker ps --format "{{.Names}}" 2>/dev/null | grep -qx "$1"; }
WITH_UI=true; [ "${1:-}" = --no-ui ] && WITH_UI=false
if running mycache-redis && { ! $WITH_UI || running mycache-redis-ui; }; then ok "Redis already running"; exit 0; fi
# Standalone: the shared Docker network this compose joins — created if missing, so the
# project works without myworkspace (same name and subnet the workspace uses).
docker network inspect my_docker_network >/dev/null 2>&1 \
    || docker network create --subnet=172.28.0.0/16 my_docker_network >/dev/null
bash "$SCRIPT_DIR/start.sh" "$@" || { err "start.sh failed"; exit 1; }
running mycache-redis && ok "Redis running" || { err "Redis container is not running after start.sh"; exit 1; }
