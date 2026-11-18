#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# credentials_check.sh — mycache's ISSUED credentials: the keys mycache issues (it is the server) — any that need you?
#
# What for    mycache is the server of the Redis password: it issues it, everyone else (Plane, …) only uses it.
#             This runs every *_check.sh in this folder — one per key and kind — and shows ONLY the ones that
#             need you: 🔑 rotation (…_rotation_check.sh) — a password near / past the 90-day rule, a REMINDER,
#             nothing stops · 🎫 expiry (…_expiry_check.sh) — a key the system switches off on a date.
#             A key with time left prints nothing (CONFMGT [8.6]).
# Who         mycache's start.sh and stop.sh (so every workspace startup / shutdown) · you, any time.
# How         bash projectspace/platform/mycache/cache-agent/issued_credentials/credentials_check.sh
# Steps       1. every *_check.sh beside this file (not itself), in name order, with --quiet (silent while fine)
#             2. their lines as they come · the exit code = the worst one
# Output      [ WARN ] mycache · Redis password: rotate in 5 days (due 2027-01-03 · 90-day rule)
#                      do: bash projectspace/platform/mycache/cache-agent/issued_credentials/redis_password_rotate.sh
#             (nothing at all while every key has more than WARN_BEFORE_DAYS left)
# Errors      exit 0 all fine · 1 one needs you soon / is overdue (rotation: a reminder) · 2 one has expired ·
#             3 one could not be read (kms down …) — start.sh / stop.sh never stop because of it
# Next        a new key = a new <key>_rotation_check.sh (+ .py) and <key>_rotate.sh here — found by itself,
#             nothing else changes · keys ANOTHER system gave mycache (it only uses them) go in ../used_credentials/
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/credentials_check.py" "$@"
