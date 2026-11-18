#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_status.sh — is the cache-agent answering on :8892?
#
# Who         You, or scripts with --state.
#
# How         bash cache-agent/host_status.sh            human
#             bash cache-agent/host_status.sh --state    one word: running / stopped
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/host_lifecycle/host_status.py" "$@"
