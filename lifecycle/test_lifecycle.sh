#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_lifecycle.sh — mycache's lifecycle doors against a FAKE docker: the old bash and the new Python side by side
#
# What for    Proves start · stop · status · state · ensure_running · ensure_stopped · destroy · logs · the container
#             login print the same lines, give the same exit codes and make the same docker calls as the bash did
#             (CLAUDEWORK-454) — without touching the running stack, kms or any secret.
#
# Who         Claude (3a in the branch, 3c on main) · or you.
#
# Steps       L0–L13 (see the top of test_lifecycle.py)
#
# How         bash ~/myworkspace/projectspace/platform/mycache/lifecycle/test_lifecycle.sh
#
# Output      [ PASS ] / [ FAIL ] per check · last line: ALL PASS — old = new   or   N FAILED (exit 1)
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/test_lifecycle.py" "$@"
