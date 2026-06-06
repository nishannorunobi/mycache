#!/bin/sh
# stop.sh — Stop the running cache-agent process inside the container.
set -eu

if pkill -f '[u]vicorn server:app' 2>/dev/null; then
    printf '\033[32m[ OK ]\033[0m  Cache agent stopped.\n'
else
    printf '\033[33m[WARN]\033[0m  No running cache-agent server found.\n'
fi
