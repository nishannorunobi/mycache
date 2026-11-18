#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# logs.sh — follow mycache's container logs
#
# Who         You.
#
# How         bash logs.sh
#
# Output      the last 100 lines, then live — Ctrl+C to stop
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/logs.py" "$@"
