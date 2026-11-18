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
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/state.py" "$@"
