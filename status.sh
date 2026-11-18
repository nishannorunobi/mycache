#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# status.sh — show mycache's containers (human view)
#
# What for    See whether Redis and its web UI run, and their ports.
#
# Who         You.
#
# How         bash status.sh
#
# Output      NAME            STATUS                 PORTS
#             mycache-redis   Up 2 hours (healthy)   0.0.0.0:6379->6379/tcp
#
# Next        For scripts: bash state.sh (one word)
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/status.py" "$@"
