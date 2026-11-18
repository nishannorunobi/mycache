#!/usr/bin/env python3
"""health.py — (inside the container) print ok / down: does the agent answer /health on :$PORT (default 8892)?

The door: ../health.sh (its --help). Always exit 0 — the word is the answer.
"""
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import container_door as d

try:
    with urllib.request.urlopen(f"http://localhost:{os.environ.get('PORT') or 8892}/health", timeout=10) as r:
        up = 200 <= r.status < 400
except Exception:                         # refused · timeout · an HTTP error = down (curl -sf)
    up = False
d.say("ok" if up else "down")
