# ensure_stopped.sh — Stop mycache only if it runs (safe to run any number of times).

**Who runs it:** The workspace shutdown (svcmgt).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash ensure_stopped.sh
[  OK  ] already stopped
```

**What it does:**
1. running → calls `stop.sh` · else says "already stopped"
