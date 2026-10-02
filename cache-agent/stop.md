# stop.sh — Stop the agent's web server — runs INSIDE the container.

**Who runs it:** `host_stop.sh`.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ (inside the container) sh /cache-agent/stop.sh
stopped
```

**What it does:**
1. stops uvicorn
