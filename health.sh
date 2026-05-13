#!/bin/bash
# health.sh — Exit 0 if mycache-redis container is running, 1 otherwise.
docker inspect -f '{{.State.Running}}' mycache-redis 2>/dev/null | grep -q '^true$'
