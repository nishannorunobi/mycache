# logs.sh — Follow mycache's container logs.

**Who runs it:** You.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash logs.sh
(last 100 lines, then live — Ctrl+C to stop)
```

**What it does:**
1. `docker compose logs -f --tail=100`
