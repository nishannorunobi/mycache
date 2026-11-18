#!/usr/bin/env python3
"""ensure_running.py — start mycache only if it is not running; safe any number of times. The door: ../ensure_running.sh."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod

if pod.starter:
    pod.starter.start()

with_ui = sys.argv[1:2] != ["--no-ui"]
if pod.running("mycache-redis") and (not with_ui or pod.running("mycache-redis-ui")):
    pod.ok("Redis already running")
    sys.exit(0)

# Standalone: the shared Docker network this compose joins — made if missing, so the project works without
# myworkspace (the same name and subnet the workspace uses).
if pod.docker("network", "inspect", "my_docker_network", quiet=True):
    import subprocess
    subprocess.run(["docker", "network", "create", "--subnet=172.28.0.0/16", "my_docker_network"],
                   stdout=subprocess.DEVNULL)

if pod.door("start.sh", *sys.argv[1:]):
    pod.die("start.sh failed")
if pod.running("mycache-redis"):
    pod.ok("Redis running")
else:
    pod.die("Redis container is not running after start.sh")
