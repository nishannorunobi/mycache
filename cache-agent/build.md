# build.sh — Install Python + the agent's dependencies (venv) — runs INSIDE the container.

**Who runs it:** `host_start.sh` calls it when the venv is missing (first build needs network).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ docker exec mycache-redis sh /cache-agent/build.sh
Dependencies installed. · agent.conf created (no secrets — they come from kms at start).
```

**What it does:**
1. creates `.venv`, installs `requirements.txt`, creates `agent.conf` from the example (no secrets)
