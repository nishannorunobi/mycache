#!/usr/bin/env python3
"""host_status.py — does the cache-agent answer on :8892? human line · --state: one word running / stopped.

The door: ../host_status.sh (its --help). No mirror log (scripts read the one word).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_door as a

a.help_only()
s = "running" if a.answers(3) else "stopped"
print(s if sys.argv[1:2] == ["--state"] else f"Cache agent (:8892) inside mycache-redis: {s}")
