#!/usr/bin/env python3
"""credentials_check.py — mycache's ISSUED credentials: runs every *_check.sh beside it and shows ONLY what needs you.

The door: credentials_check.sh (its --help). start.sh and stop.sh call it on every startup / shutdown.
SILENT on screen while every key has time left: each check runs with --quiet, its lines (if any) are shown and
everything goes to the mirror log only — never the screen's "[logging] →" line. Exit = the worst check's exit code
(0 fine · 1 needs you soon / overdue · 2 expired · 3 could not be read) — start / stop never stop because of it.
A new key = a new <key>_rotation_check.sh (+ .py) here — found by itself, nothing else changes.
"""
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in HERE.parents if (p / "mountspace").is_dir()][:1]
try:
    import starter
except ImportError:                                   # a temp copy: no --help, no log — as the bash
    starter = None

DOOR = os.environ.pop("STARTER", "") or str(HERE / "credentials_check.sh")
if starter and sys.argv[1:2] in (["-h"], ["--help"]):
    print(starter.header_help(DOOR))
    sys.exit(0)

LOG = None
if starter:
    try:
        path = starter.mirror_log_path(DOOR)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        LOG = open(path, "a")
    except OSError:
        LOG = None


def log(line):
    if LOG:
        try:
            LOG.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")
            LOG.flush()
        except OSError:
            pass


worst, n = 0, 0
for check in sorted(HERE.glob("*_check.sh")):
    if check.name == "credentials_check.sh":
        continue
    r = subprocess.run(["bash", str(check), "--quiet"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out = r.stdout.rstrip("\n")
    n += 1
    if out:
        print(out, flush=True)
        for line in out.split("\n"):
            log(line)
    log(f"{check.name} → exit {r.returncode}")
    worst = max(worst, r.returncode)
log(f"{n} key(s) checked · worst exit {worst}")
sys.exit(worst)
