#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — (inside the container) the cache-agent is already running: it is the entry point
#
# What for    Older callers (the Docker dashboard) run this to start the agent. The agent
#             now starts with the container (supervisor.py), so this only reports.
#
# Who         The Docker dashboard, or you inside the container.
#
# How         sh /cache-agent/start.sh
#
# Output      [OK] cache-agent is running on :8892 (started by supervisor.py)
#
# Errors      not answering → the supervisor restarts it by itself; reason: docker logs mycache-redis
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/in_container/start.py" "$@"
