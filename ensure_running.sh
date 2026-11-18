#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ensure_running.sh — start mycache only if it is not running
#
# What for    Safe to run any number of times.
#
# Who         The workspace startup (svcmgt).
#
# How         bash ensure_running.sh [--no-ui]
#
# Steps       1. running already → says so
#             2. otherwise → start.sh (same arguments), then checks it runs
#
# Output      [  OK  ] Redis running
#
# Errors      the same as start.sh (e.g. kms sealed)
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/ensure_running.py" "$@"
