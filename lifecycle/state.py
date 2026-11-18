#!/usr/bin/env python3
"""state.py — one word for scripts (svcmgt): running / stopped. No mirror log — scripts read the one word.

The door: ../state.sh (its --help).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod

pod.help_only()
print("running" if pod.running("mycache-redis") else "stopped")
