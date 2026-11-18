#!/usr/bin/env python3
"""mycache_container_login.py — a shell INSIDE a running mycache container. The door: ../mycache_container_login.sh.

The session itself is NOT mirror-logged: the log pipe is no terminal (no prompt, no keys) and would record
everything typed — the shell gets the real terminal back.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod

if pod.starter:
    pod.starter.start()

CONTAINERS = ["mycache-redis", "mycache-redis-ui"]
c = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else "mycache-redis"
if c not in CONTAINERS:
    pod.die(f"'{c}' is not one of mycache's containers: {' '.join(CONTAINERS)}")
if pod.docker("info", quiet=True):
    pod.die("Docker is not running (or this login is not in the docker group yet)")
if not subprocess.run(["docker", "ps", "-q", "-f", f"name=^{c}$"], stdout=subprocess.PIPE, text=True).stdout.strip():
    pod.die(f"{c} is not running — start it: bash {pod.POD}/ensure_running.sh")
try:
    tty = os.open("/dev/tty", os.O_RDWR)
except OSError:
    pod.die("this needs a terminal (run it yourself, not from another script)")
shell = "bash" if pod.docker("exec", c, "sh", "-c", "command -v bash", quiet=True) == 0 else "sh"
pod.ok(f"entering {c} ({shell}) — exit = back here, the container keeps running")
pod.info("careful: the Redis data is REAL (Plane's cache and queues)")
sys.stdout.flush()
sys.stderr.flush()
for fd in (0, 1, 2):
    os.dup2(tty, fd)
os.execvp("docker", ["docker", "exec", "-it", c, shell])
