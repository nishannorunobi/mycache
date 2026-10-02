# host_status.sh — Is the cache-agent answering on :8892?

**Who runs it:** You (human) or scripts (`--state`).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash cache-agent/host_status.sh           # human
$ bash cache-agent/host_status.sh --state   # one word
running
```

**What it does:**
1. calls `http://localhost:8892/health`
