#!/bin/bash
# ────────────────────────────────────────────────────────
# test_credentials.sh — automatic tests of mycache's issued credentials (issued_credentials/), on a THROWAWAY kms only
#
# What for    Prove the Redis password's rotation reminder (CONFMGT [8.6]): silent while more than WARN_BEFORE_DAYS
#             are left · ⚠ + "do:" within them · ⚠ overdue (a reminder, never "expired") · the right "cannot tell"
#             lines — without ever touching the real kms, the real login, the real password or the running stack.
# Who         Claude (auto test in the branch, then on main) · the owner by hand.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/test_credentials.sh   (~40 s · throwaway kms on :8122)
# Cases       C0 static: every .sh answers --help, bash -n, the .py compile · start.sh / stop.sh call credentials_check.sh
#                (never failing: || true) · the runner finds *_check.sh by itself
#             C1 fine (90-day rule, written today): by hand OK + "rotate by", exit 0 · --quiet + the runner: nothing, exit 0
#             C2 within the window (a 3-day rule): exit 1, WARN "rotate in 3 days" + "do: bash …redis_password_rotate.sh" ·
#                the runner shows it, exit 1
#             C3 overdue ("today" = 100 days on): exit 1 (never 2), WARN "overdue by 10 days … nothing stops" + "do:"
#             C4 kms down: exit 3, WARN, never the real kms (KMS_URL set = the only one tried)
#             C5 not signed up: exit 3, WARN + the sign-up line
#             C6 credentials.conf missing / garbage → 7 and 90 + a WARN each
#             C7 SECRET_MGT=local → OK "no kms date", exit 0 · L1 the password never on screen
#             OLD every case also on the old bash (git 709477f) → the same lines + exit codes
# Errors      [ERROR] <case> … — FAILED at the end, exit 1
# ────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/test_credentials.py" "$@"
