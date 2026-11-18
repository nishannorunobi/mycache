#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# mycache_container_login.sh — a shell INSIDE mycache's running container, to look around (MYCACHE)
#
# What for    One command instead of remembering: docker exec -it <container> bash|sh. A container has no SSH
#             and no login prompt — this is the way in. Type exit to come back; the container keeps running.
# Steps       1. the container: mycache-redis (the default)
#                or another one as the argument: mycache-redis-ui
#             2. checks it runs (else: how to start it)
#             3. a short reminder, then the shell — bash if the image has it, else sh
# How         bash ~/myworkspace/projectspace/platform/mycache/mycache_container_login.sh          (or: … mycache-redis-ui)
# Careful     the Redis data is REAL (Plane's cache and queues) — look, do not change.
# See also    a single command without a shell: docker exec mycache-redis <command>
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/mycache_container_login.py" "$@"
