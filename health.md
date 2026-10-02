# health.sh — Exit code only: 0 = the mycache-redis container runs, 1 = not.

**Who runs it:** Scripts / checks.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash health.sh; echo $?
0
```

**What it does:**
1. checks the container
