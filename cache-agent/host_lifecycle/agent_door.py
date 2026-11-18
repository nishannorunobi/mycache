#!/usr/bin/env python3
"""agent_door.py — what the cache-agent's host programs share (host_start · host_status · host_stop).

    AGENT · POD          cache-agent/ · the pod (projectspace/platform/mycache)
    AGENT_URL            the agent's address (CACHE_AGENT_URL, default http://localhost:8892 — as the bash)
    answers(timeout)     does the agent answer /health?  (the bash: curl -fsS --max-time N -o /dev/null)
    help_only()          --help from the door's header, for a program that keeps no mirror log
    mirror_log()         --help · the mirror log; the agent's own log folder written by its container (root) →
                         the log goes next to it: …/mycache/cache-agent_<name>_sh.log (as the bash)
Standard library only.
"""
import os
import pathlib
import sys
import urllib.request

AGENT = pathlib.Path(__file__).resolve().parent.parent
POD = AGENT.parent
AGENT_URL = os.environ.get("CACHE_AGENT_URL", "http://localhost:8892").rstrip("/")
sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in POD.parents if (p / "mountspace").is_dir()][:1]
try:
    import starter
except ImportError:                       # a temp copy: no --help, no mirror log — as the bash
    starter = None


def answers(timeout):
    try:
        with urllib.request.urlopen(f"{AGENT_URL}/health", timeout=timeout) as r:
            return 200 <= r.status < 400
    except Exception:                     # refused · timeout · an HTTP error = does not answer (curl -f)
        return False


def _door():
    return os.environ.pop("STARTER", "") or sys.argv[0]


def help_only():
    door = _door()
    if starter and sys.argv[1:2] in (["-h"], ["--help"]):
        print(starter.header_help(door))
        sys.exit(0)


def mirror_log():
    if not starter:
        return
    door = _door()
    if sys.argv[1:2] in (["-h"], ["--help"]):
        print(starter.header_help(door))
        sys.exit(0)
    folder = os.path.dirname(starter.mirror_log_path(door))
    try:
        os.makedirs(folder, exist_ok=True)
    except OSError:
        pass
    if not os.access(folder, os.W_OK):    # root-owned (the container writes it) → right next to it
        door = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(door))),
                            f"{os.path.basename(os.path.dirname(os.path.abspath(door)))}_{os.path.basename(door)}")
    starter.start_mirror_log(door)
