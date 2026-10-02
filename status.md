# status.sh — Show mycache's containers and their state (human view).

**Who runs it:** You.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash status.sh
NAME            STATUS                 PORTS
mycache-redis   Up 2 hours (healthy)   0.0.0.0:6379->6379/tcp
```

**What it does:**
1. `docker compose ps`

**Next / errors:** For scripts use `state.sh` (one word).
