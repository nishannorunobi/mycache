# health.sh — Print `ok` / `down` — is the agent answering? (inside the container)

**Who runs it:** Scripts.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ (inside the container) sh /cache-agent/health.sh
ok
```

**What it does:**
1. calls `http://localhost:8892/health`
