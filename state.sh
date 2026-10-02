#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# state.sh — one word for scripts: running / stopped
#
# What for    Tell the workspace (svcmgt status_all) whether mycache-redis runs.
#
# Who         Scripts.
#
# How         bash state.sh
#
# Output      running
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'mycache-redis' && echo running || echo stopped
