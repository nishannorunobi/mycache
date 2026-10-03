# mycache

Redis cache for the workspace (Plane uses it) + **redis-commander** (web UI, :8081) +
**cache-agent** (AI helper, :8892, runs inside the Redis container).

```
bash start.sh [--no-ui]   # start Redis (+ UI)        bash stop.sh    # stop (data kept)
bash status.sh            # containers                bash logs.sh    # tail logs
bash cache-agent/host_start.sh                         # start the cache-agent
```

## 🔑 Where are the secrets?

**Not in any file of this project.** They live in **kms** (the workspace's key management
system, OpenBao). In `.env` a secret's value is **its kms address** — the container fetches
the real value itself every time it starts:

```
REDIS_PASSWORD=http://kms-openbao:8200/v1/kv/data/mycache/redis
```

| Secret | Used by | Where it lives | Fetched by |
|---|---|---|---|
| `REDIS_PASSWORD` | Redis server, redis-commander | kms `kv/mycache/redis` | the container itself: `connect_external/kms/fetch_from_kms.py` (Redis UI: from a RAM volume) |
| `REDIS_PASSWORD` | cache-agent | kms `kv/mycache/redis` | `cache-agent/host_start.sh` (its own kms login) |
| `ANTHROPIC_API_KEY` | cache-agent | kms `kv/shared/anthropic` | `cache-agent/host_start.sh` |

- `.env` lists every key the containers need — plain values, and kms addresses for secrets. It
  is in git on purpose (no secret in it). A plain value instead of the address also works (a quick
  test without kms) — never commit that; `test_kms.sh` checks it.
- **New secret?** Never into a config file: `bash connect_external/kms/add_new_secret_to_kms.sh <KEY>`
  (cache-agent: `bash cache-agent/connect_external/kms/add_new_secret_to_kms.sh <KEY>`), then add
  `<KEY>=http://kms-openbao:8200/v1/kv/data/mycache/redis` to `.env` (and pass it in `docker-compose.yml`).
- **See / change a secret:** kms UI http://127.0.0.1:8110/ui → Method *Username* (owner
  login) → *Secrets engines* → `kv` → `mycache` → `redis`. Or `bash
  projectspace/kms/set_secret.sh mycache/redis REDIS_PASSWORD` (hidden input).
  After a change: `bash stop.sh && bash start.sh`.
- **Connecting by hand** (redis-cli): `REDISCLI_AUTH=<password> redis-cli -h 127.0.0.1 ping` —
  never `-a <password>` (it shows in the process list).
- **kms sealed** → the container stops with *"kms is SEALED"* (`docker logs mycache-redis`):
  unseal it (startup prompt or the kms UI) — it retries by itself. A running Redis keeps working.
- **First time:** each component signs itself up with kms (once, asks the kms owner's password):
  Redis server: `bash start.sh` by hand does it (or `bash connect_external/kms/signup_with_kms.sh`) ·
  cache-agent `bash cache-agent/connect_external/kms/signup_with_kms.sh`
- **Every script explains itself:** `bash <script> --help` (or read its header).
- How mycache talks to kms: [`connect_external/kms/`](connect_external/kms/) —
  network calls only, no kms file is used, so mycache and kms can run on **different
  machines**: put that kms's address in the `.env` line (`https://<kms-host>:<port>/v1/kv/data/…`).
- **Image:** mycache runs its own image `mycache-redis` (Redis + Python, `dockerspace/Dockerfile`) —
  built once by `start.sh` (needs the internet once), then offline.
