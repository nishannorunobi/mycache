#!/usr/bin/env python3
"""stop.py — stop mycache (Redis + the web UI), the data is kept. The door: ../stop.sh (its --help)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod
from pod import BOLD, GREEN, OFF, YELLOW

if pod.starter:
    pod.starter.start()

os.chdir(pod.POD)
# Reminder (CONFMGT [8.6]): the keys mycache ISSUES — a reminder only, never stops this program.
pod.door("cache-agent/issued_credentials/credentials_check.sh")

print(f"{YELLOW}==> Stopping Redis...{OFF}", flush=True)
rc = pod.docker("compose", "down")
if rc:
    sys.exit(rc)
print(f"{GREEN}    Redis stopped. Data is preserved in Docker volumes.{OFF}")
print(f"    Run {BOLD}./start.sh{OFF} to bring it back up.")
