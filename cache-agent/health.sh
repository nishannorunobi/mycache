#!/bin/sh
# health.sh — Quick liveness check for the cache-agent.
curl -sf http://localhost:${PORT:-8892}/health >/dev/null 2>&1 && echo "ok" || echo "down"
