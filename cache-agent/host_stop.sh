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
STARTER="$0" exec python3 -u "$(dirname "$0")/host_lifecycle/host_stop.py" "$@"
