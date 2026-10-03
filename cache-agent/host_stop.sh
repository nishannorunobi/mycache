#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_stop.sh — the cache-agent cannot be stopped alone
#
# What for    The agent is the container's entry point and runs Redis as its child —
#             stopping it means stopping Redis. This script only says so.
#
# Who         You, or the workspace shutdown (svcmgt) — it is a no-op there.
#
# How         bash cache-agent/host_stop.sh        → a note, exit 0
#             bash stop.sh                         → stops Redis AND the agent
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -euo pipefail
echo "[INFO] the cache-agent runs with Redis (it is the container's entry point) — nothing stopped."
echo "       To stop both: bash $(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/stop.sh"
exit 0
