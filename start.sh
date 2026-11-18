#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — start mycache: the Redis cache (+ web UI on :8081)
#
# What for    Start Redis. The cache-agent is the container's entry point: it gets the
#             password from kms (cache-agent/agent.conf = kms addresses), starts Redis
#             and serves its API on :8892 — never a password from a file.
#
# Who         You, or the workspace startup (via ensure_running.sh).
#
# How         bash start.sh             Redis + web UI
#             bash start.sh --no-ui     Redis only
#
# Steps       1. first time only: the cache-agent signs itself up with kms as it starts (your kms password from
#                kms's master_password, .env KMS_MASTER_PASSWORD_DIR) — file empty → asks here, by hand only
#             2. docker compose up -d — builds the image once (internet once), then:
#                inside: cache-agent/supervisor.py → kms → Redis + the agent API
#
# Output      ==> Redis is up
#                 Password  : in kms (kv/mycache/redis)
#
# Errors      kms is SEALED          → unseal kms — the container retries by itself
#                                     (see why: docker logs mycache-redis)
#             not signed up, master_password empty → put your kms password there, or run bash start.sh by hand once
#             the agent / Redis failed  → docker logs mycache-redis ([agent] lines say why)
#
# Next        bash status.sh  ·  bash stop.sh
# ─────────────────────────────────────────────────────────────────────────────
# the pod guard: this pod sits at its folder of ccc/scripts/gitmgt/repos.conf — its relative mounts reach THIS workspace's
# mountspace/, else Docker would quietly make EMPTY data folders elsewhere (CLAUDEWORK-258). Kept here, not in the .py:
# test_move_repos M6 runs this very line.
cd "$(dirname "$0")" && _WS_ROOT="$(python3 lifecycle/pod.py)"
[ "$(cd "$PWD/../../../mountspace" 2>/dev/null && pwd)" = "$_WS_ROOT/mountspace" ] || { echo -e "\033[31m[ERROR]\033[0m  ../../../mountspace from $PWD is not this workspace's mountspace/ — this pod is not at its folder (ccc/scripts/gitmgt/repos.conf): bash ccc/scripts/gitmgt/move_repos_to_new_folders.sh"; exit 1; }
STARTER="$PWD/start.sh" exec python3 -u lifecycle/start.py "$@"
