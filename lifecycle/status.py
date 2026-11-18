#!/usr/bin/env python3
"""status.py — mycache's containers, the human view (docker compose ps). The door: ../status.sh (its --help)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod
from pod import BOLD, OFF

if pod.starter:
    pod.starter.start()

print(f"{BOLD}==> Redis container status{OFF}", flush=True)
sys.exit(pod.docker("compose", "ps"))
