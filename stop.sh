#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# stop.sh — stop mycache (Redis + web UI); the data is kept
#
# What for    Stop the containers. Cached data stays in the Docker volume.
#
# Who         You, or the workspace shutdown (via ensure_stopped.sh).
#
# How         bash stop.sh
#
# Output      ==> Stopping Redis...
#                 Redis stopped. Data is preserved in Docker volumes.
#
# Note        Plane uses this Redis — it shows errors until mycache runs again.
#
# Next        bash start.sh
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/stop.py" "$@"
