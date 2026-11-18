#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ensure_stopped.sh — stop mycache only if it runs
#
# What for    Safe to run any number of times.
#
# Who         The workspace shutdown (svcmgt).
#
# How         bash ensure_stopped.sh
#
# Steps       1. running → stop.sh
#             2. otherwise → "already stopped"
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/ensure_stopped.py" "$@"
