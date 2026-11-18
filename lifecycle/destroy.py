#!/usr/bin/env python3
"""destroy.py — ⚠ stop mycache AND delete all its data, after you type yes. The door: ../destroy.sh (its --help)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod
from pod import BOLD, OFF, RED, YELLOW

if pod.starter:
    pod.starter.start()


def ask(question):
    """The answer typed; the question goes straight to the terminal (the mirror log only shows whole lines)."""
    if sys.stdin.isatty():
        try:
            with open("/dev/tty", "w") as tty:
                tty.write(question)
        except OSError:
            pass
    line = sys.stdin.readline()
    if not line:                                          # no input at all: the bash `read` failed → exit 1
        sys.exit(1)
    return line.rstrip("\n")


print(f"{RED}{BOLD}WARNING: This will permanently delete all Redis data.{OFF}", flush=True)
if ask("Type 'yes' to confirm: ") != "yes":
    print("Aborted.")
    sys.exit(0)

print(f"{YELLOW}==> Stopping and removing Redis containers + volumes...{OFF}", flush=True)
rc = pod.docker("compose", "down", "-v", "--remove-orphans")
if rc:
    sys.exit(rc)
print(f"{RED}    All Redis data deleted.{OFF}")
print(f"    Run {BOLD}./start.sh{OFF} to start fresh.")
