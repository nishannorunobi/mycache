#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# test_agent_doors.sh — the cache-agent's doors (host_start · host_status · host_stop · health · start) on fakes
#
# What for    Proves the Python versions answer as the bash did (CLAUDEWORK-454): old = new read-only on this PC,
#             then a fake agent + a fake docker for every path (start · never answers · log next to a root folder)
#             — nothing real started, stopped or changed.
#
# Who         Claude (3a in the branch, 3c on main) · or you.
#
# Steps       H0–H7 (see the top of test_agent_doors.py)
#
# How         bash ~/myworkspace/projectspace/platform/mycache/cache-agent/test_agent_doors/test_agent_doors.sh
#
# Output      [ PASS ] / [ FAIL ] per check · last line: ALL PASS   or   N FAILED (exit 1)
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/test_agent_doors.py" "$@"
