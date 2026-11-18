#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — ⚠ stop mycache AND delete all its data (full reset)
#
# What for    Start over with an empty cache. The data is gone for good.
#
# Who         You only, on purpose.
#
# How         bash destroy.sh
#
# Steps       1. asks you to confirm
#             2. docker compose down -v — containers + data volume removed
#
# Note        Plane loses its cache (it rebuilds it). Secrets in kms are not touched.
#
# Next        bash start.sh
# ─────────────────────────────────────────────────────────────────────────────
STARTER="$0" exec python3 -u "$(dirname "$0")/lifecycle/destroy.py" "$@"
