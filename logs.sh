#!/bin/bash
# logs.sh — Tail logs for the Redis cache container.
# Usage:
#   ./logs.sh   → tail all logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker compose logs -f --tail=100
