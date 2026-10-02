# state.sh — One word for scripts: `running` / `stopped` (container mycache-redis).

**Who runs it:** The workspace (svcmgt `status_all`), other scripts.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash state.sh
running
```

**What it does:**
1. checks whether container `mycache-redis` runs

**Next / errors:** Human view: `status.sh`.
