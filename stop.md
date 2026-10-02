# stop.sh — Stop mycache (Redis + UI). The cached data is kept (Docker volume).

**Who runs it:** You, or `ensure_stopped.sh` / the workspace shutdown.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash stop.sh
==> Stopping Redis...
    Redis stopped. Data is preserved in Docker volumes.
```

**What it does:**
1. `docker compose down` — containers removed, volume `mycache-redis` kept

**Next / errors:** ⚠️ Plane uses this Redis — it errors (HTTP 500) until mycache runs again: `bash start.sh`.
