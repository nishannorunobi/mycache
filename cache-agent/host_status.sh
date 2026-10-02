#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_status.sh — is the cache-agent answering on :8892?
#
# Who         You, or scripts with --state.
#
# How         bash cache-agent/host_status.sh            human
#             bash cache-agent/host_status.sh --state    one word: running / stopped
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac

set -uo pipefail
if curl -fsS --max-time 3 -o /dev/null "http://localhost:8892/health" 2>/dev/null; then s=running; else s=stopped; fi
[ "${1:-}" = --state ] && { echo "$s"; exit 0; }
echo "Cache agent (:8892) inside mycache-redis: $s"
