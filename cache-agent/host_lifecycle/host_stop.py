#!/usr/bin/env python3
"""host_stop.py — the cache-agent cannot be stopped alone (it runs Redis as its child): says so, exit 0.

The door: ../host_stop.sh (its --help). svcmgt's shutdown calls it — a no-op there.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_door as a

a.help_only()
print("[INFO] the cache-agent runs with Redis (it is the container's entry point) — nothing stopped.")
print(f"       To stop both: bash {a.POD}/stop.sh")
