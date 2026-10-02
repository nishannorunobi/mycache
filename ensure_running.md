# ensure_running.sh — Start mycache only if it is not running (safe to run any number of times).

**Who runs it:** The workspace `startup.sh` (svcmgt).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash ensure_running.sh [--no-ui]
[  OK  ] Redis running
```

**What it does:**
1. already running → says so · else runs `start.sh` (same arguments) and checks it really runs

**Next / errors:** Fails like `start.sh` (e.g. kms sealed).
