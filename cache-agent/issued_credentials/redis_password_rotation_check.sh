#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# redis_password_rotation_check.sh — the 90-day reminder for ONE issued key: when is mycache's Redis password due for a new value?
#
# What for    mycache ISSUES the Redis password. It never expires — the rotation rule (KMS-79) says: a new value
#             ROTATE_AFTER_DAYS (credentials.conf, default 90) after its last change, so a copied old one becomes
#             useless. This reads the date of the last change from kms (mycache's own login, no password, the value
#             is never shown) and says how long is left. A REMINDER only — nothing stops when it is overdue.
# Who         You, any time · credentials_check.sh (start.sh / stop.sh) with --quiet: silent while more than
#             WARN_BEFORE_DAYS (credentials.conf, default 7) are left.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotation_check.sh
# Output      [  OK  ] mycache · Redis password changed 2026-10-05 — rotate by 2027-01-03, 56 days left (reminds at 7)
#             [ WARN ] mycache · Redis password: rotate in 5 days (due 2027-01-03 · 90-day rule)
#                      do: bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotate.sh
#             [ WARN ] mycache · Redis password: rotation overdue by 3 days (was due …) — nothing stops
# Errors      exit 0 fine · 1 due within WARN_BEFORE_DAYS or overdue (a reminder) · 3 cannot tell (kms down ·
#             not signed up · the entry not readable)
# Next        bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotate.sh — a new value
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/redis_password_rotation_check.py" "$@"
