#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# host_start.sh — make sure the cache-agent (Redis's assistant, :8892) is running
#
# What for    The agent is the mycache container's entry point: it starts with Redis and
#             stays on. So "start the agent" = make sure the container runs.
#
# Who         You, or the workspace startup (svcmgt).
#
# How         bash cache-agent/host_start.sh
#
# Steps       1. already answering on :8892 → nothing to do
#             2. container not running → bash ../start.sh (signs the agent up once, by hand)
#             3. wait until :8892 answers (the supervisor restarts the API by itself)
#
# Output      [OK] Cache agent running on :8892
#
# Errors      container up but no answer → docker logs mycache-redis ([agent] lines say why:
#                                          kms sealed / not signed up / key missing)
#
# Next        bash cache-agent/host_status.sh  ·  stop = bash stop.sh (Redis and agent together)
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/host_lifecycle/host_start.py" "$@"
