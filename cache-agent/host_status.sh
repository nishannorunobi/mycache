#!/bin/bash
# host_status.sh — is the cache-agent (Cache agent) answering on :8892?
#   bash host_status.sh            # human
#   bash host_status.sh --state    # one word: running / stopped
set -uo pipefail
if curl -fsS --max-time 3 -o /dev/null "http://localhost:8892/health" 2>/dev/null; then s=running; else s=stopped; fi
[ "${1:-}" = --state ] && { echo "$s"; exit 0; }
echo "Cache agent (:8892) inside mycache-redis: $s"
