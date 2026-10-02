# start.sh — Start mycache: the Redis cache (+ the redis-commander web UI on :8081).

**Who runs it:** You, or the workspace `startup.sh` (svcmgt calls `ensure_running.sh`).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash start.sh            # Redis + UI
$ bash start.sh --no-ui    # Redis only
==> Starting Redis 7-alpine...
==> Redis is up
    Host      : 0.0.0.0:6379
    Password  : in kms (kv/mycache/redis — UI http://127.0.0.1:8110/ui)
```

**What it does:**
1. reads the plain settings in `.env` (version, port, `KMS_URL`)
2. gets `REDIS_PASSWORD` from **kms** (`connect_external/kms/kms_secrets.sh`) — never printed, never a file
3. `docker compose up -d` — the password goes to the container's env → `/run/redis.conf` in RAM

**Next / errors:** kms SEALED → unseal kms, then again · `no kms login files` → `bash connect_external/kms/register_to_kms.sh` first. Stop: `bash stop.sh`.
