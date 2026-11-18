#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# health.sh — print ok / down: is the agent answering? (inside the container)
#
# Who         Scripts.
#
# How         (inside the container)  sh /cache-agent/health.sh
#
# Output      ok
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/in_container/health.py" "$@"
