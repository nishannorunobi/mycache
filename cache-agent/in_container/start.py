#!/usr/bin/env python3
"""start.py — (inside the container) the cache-agent is already running: supervisor.py starts it with the container.

The door: ../start.sh (its --help) — older callers (the Docker dashboard) still run it; this only reports:
answers on PORT (agent.conf, default 8892) → OK exit 0 · else WARN exit 1 (the supervisor restarts it by itself).
"""
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import container_door as d

AGENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
found = re.findall(r"^PORT=(.*)$", open(os.path.join(AGENT, "agent.conf"), errors="replace").read(), re.M)
port = found[0].split("=")[0].replace(" ", "") if found else ""
port = port or "8892"
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=10) as r:
        up = 200 <= r.status < 400
except Exception:
    up = False
if up:
    d.say(f"\033[32m[  OK  ]\033[0m cache-agent is running on :{port} (started by supervisor.py, the container entry point)")
    sys.exit(0)
d.say(f"\033[33m[WARN]\033[0m   cache-agent is not answering on :{port} — supervisor.py restarts it by itself; "
      f"reason: docker logs mycache-redis")
sys.exit(1)
