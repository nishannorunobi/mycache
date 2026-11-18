#!/usr/bin/env python3
"""ensure_stopped.py — stop mycache only if it runs; safe any number of times. The door: ../ensure_stopped.sh."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod
from pod import GREEN, OFF

if pod.starter:
    pod.starter.start()

if not {"mycache-redis", "mycache-redis-ui"} & set(pod.names()):
    print(f"{GREEN}[  OK  ]{OFF} Redis (mycache) already stopped", flush=True)
    sys.exit(0)
sys.exit(pod.door("stop.sh", *sys.argv[1:]))
