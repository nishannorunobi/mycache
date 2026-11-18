#!/usr/bin/env python3
"""logs.py — follow mycache's container logs: the last 100 lines, then live (Ctrl+C stops). The door: ../logs.sh."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod

if pod.starter:
    pod.starter.start()

try:
    sys.exit(pod.docker("compose", "logs", "-f", "--tail=100"))
except KeyboardInterrupt:
    sys.exit(130)
