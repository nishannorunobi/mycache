#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cache_transfer_kms2local.sh — mycache (cache-agent): every password read from kms and written into agent.conf as the plain
#                                 value · SECRET_MGT=local (TESTSERVER-75)
#
# What for    "local deploy": the component runs on the real passwords in its own config — no kms at all. Each kms
#             address stays in the comment right above its line (# kms: …), so cache_transfer_local2kms.sh switches back.
# Who         You — or svcmgt/transfer_all_kms2local.sh (every component, one kms login).
# How         bash cache-agent/connect_external/kms/cache_transfer_kms2local.sh      (asks your kms password; safe to run again)
# Steps       1. SECRET_MGT already local → nothing to do
#             2. each value read from kms → written on its line; a key kms does not have → NOT_FOUND_IN_KMS (+ WARN)
#             3. SECRET_MGT=local — the config now holds plain passwords: git commit/push for this repo defaults to no
# Output      [  OK  ] <KEY> ← kv/<entry>: written as the plain value       (values are never shown)
#             [  OK  ] kms → local: 2 written · 0 not found in kms — SECRET_MGT=local; …
# Errors      kms not running · login refused · a read refused → one line, the config unchanged
# Next        restart the component (its own start) — it then runs on the local values
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) awk 'NR==1{next} /^# ─/{n++; if(n==2) exit; next} n==1{ sub(/^# ?/,""); if(!t){printf "\033[1m%s\033[0m\n",$0; t=1; next} l=substr($0,1,12); if(l ~ /^[A-Z][A-Za-z ]+$/){c=(l ~ /^Errors/)?"\033[33m":"\033[36m"; printf "%s%s\033[0m%s\n",c,l,substr($0,13)} else print }' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REG_AGENT_CONF:-$(cd "$HERE/../.." && pwd)/agent.conf}"                 # REG_*: tests point elsewhere
python3 "$HERE/kms_transfer.py" kms2local --mode-conf "$CONF" --conf "$CONF"
