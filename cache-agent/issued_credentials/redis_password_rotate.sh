#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# redis_password_rotate.sh — the fix for the reminder: mycache's Redis password gets a new random value (kms + Redis)
#
# What for    The rotation reminder (redis_password_rotation_check.sh) says "do: bash …/redis_password_rotate.sh"
#             when the Redis password is near / past ROTATE_AFTER_DAYS. This is that fix, named after the key so the
#             folder explains itself — the work is mycache's existing rotation, nothing is copied:
#             cache-agent/connect_external/kms/refresh_random_secrets_to_kms.sh (CONFMGT [8.6]).
# Who         The kms owner, by hand (asks the kms password ONCE). Values are never printed.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotate.sh
# Steps       1. refresh_random_secrets_to_kms.sh: a random value → kms → Redis restarts with it → the old one refused
#             2. the reminder again: "changed <today> — rotate by <today + 90>"
# Output      [  OK  ] kv/mycache/redis  REDIS_PASSWORD stored (version 3)
#             [  OK  ] Redis has the new password — the old one is refused
#             [  OK  ] mycache · Redis password changed 2026-11-08 — rotate by 2027-02-06, 90 days left (reminds at 7)
# Errors      whatever refresh_random_secrets_to_kms.sh reports (kms down · kms and Redis disagree) — its exit code
# Next        users that keep a COPY of the password need the new one (refresh's last lines name them)
# ─────────────────────────────────────────────────────────────────────────────
# NO mirror logging on purpose: refresh_random_secrets_to_kms.sh reads the owner's kms password.
STARTER="$0" exec python3 -u "$(dirname "$0")/redis_password_rotate.py" "$@"
