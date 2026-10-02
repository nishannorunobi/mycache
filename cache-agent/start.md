# start.sh — Start the agent's web server (uvicorn) — runs INSIDE the container.

**Who runs it:** `host_start.sh` (normally you do not run it yourself).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ (inside the container) sh /cache-agent/start.sh
Cache Agent · API: http://localhost:8892
```

**What it does:**
1. checks `.venv` + `agent.conf`; needs `ANTHROPIC_API_KEY` in the environment (handed over by `host_start.sh` from kms)

**Next / errors:** `ANTHROPIC_API_KEY not set` → start it from the host: `bash cache-agent/host_start.sh`.
