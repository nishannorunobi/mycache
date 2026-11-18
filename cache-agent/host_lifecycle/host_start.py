#!/usr/bin/env python3
"""host_start.py — make sure the cache-agent (:8892) runs: it is the container's entry point, so = the container runs.

The door: ../host_start.sh (its --help). Steps: answers already → nothing · container down → ../../start.sh --no-ui ·
wait until it answers (HOST_START_TRIES, default 30 × 1 s — the supervisor inside restarts the API by itself).
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_door as a

a.mirror_log()
CONTAINER = "mycache-redis"

if a.answers(3):
    print("[OK] Cache agent already running on :8892", flush=True)
    sys.exit(0)

state = subprocess.run(["docker", "inspect", CONTAINER, "--format", "{{.State.Running}}"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
if "true" not in state:
    print(f"[INFO] {CONTAINER} is not running — starting mycache (the agent is its entry point)", flush=True)
    if subprocess.run(["bash", str(a.POD / "start.sh"), "--no-ui"]).returncode:
        sys.exit(1)

for _ in range(int(os.environ.get("HOST_START_TRIES", "30"))):
    if a.answers(2):
        print("[OK] Cache agent running on :8892", flush=True)
        sys.exit(0)
    time.sleep(1)
print(f"[ERROR] the cache-agent does not answer on :8892 — why: docker logs --tail 20 {CONTAINER}", file=sys.stderr)
logs = subprocess.run(["docker", "logs", "--tail", "5", CONTAINER], stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT, text=True).stdout
for line in logs.splitlines():
    if "[agent]" in line:
        print(line, file=sys.stderr)
sys.exit(1)
