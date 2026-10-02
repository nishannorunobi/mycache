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
system, OpenBao) and are fetched over its HTTP API every time mycache starts.

| Secret | Used by | Where it lives | Fetched by |
|---|---|---|---|
| `REDIS_PASSWORD` | Redis server, redis-commander | kms `kv/mycache/redis` | `start.sh` → container env |
| `REDIS_PASSWORD` | cache-agent | kms `kv/mycache/redis` | `cache-agent/host_start.sh` (its own kms login) |
| `ANTHROPIC_API_KEY` | cache-agent | kms `kv/shared/anthropic` | `cache-agent/host_start.sh` |

- `.env` holds only non-secret settings (version, host, port). A comment there points here.
- **New secret?** Never into a config file: `bash connect_external/kms/add_secret_to_kms.sh <KEY>`
  (cache-agent: `bash cache-agent/connect_external/kms/add_secret_to_kms.sh <KEY>`), then read it
  in the start script with `kms_get`.
- **See / change a secret:** kms UI http://127.0.0.1:8110/ui → Method *Username* (owner
  login) → *Secrets engines* → `kv` → `mycache` → `redis`. Or `bash
  projectspace/kms/set_secret.sh mycache/redis REDIS_PASSWORD` (hidden input).
  After a change: `bash stop.sh && bash start.sh`.
- **Connecting by hand** (redis-cli): `REDISCLI_AUTH=<password> redis-cli -h 127.0.0.1 ping` —
  never `-a <password>` (it shows in the process list).
- **kms sealed** → `start.sh` stops with *"kms is SEALED"*: unseal it (startup prompt or the
  kms UI), then start again. A Redis that is already running keeps working.
- **First time:** each component signs itself up with kms (once, asks the kms owner's password):
  Redis server `bash connect_external/kms/register_to_kms.sh` ·
  cache-agent `bash cache-agent/connect_external/kms/register_to_kms.sh`
- **Every script explains itself:** `bash <script> --help` (or read its header).
- How mycache talks to kms: [`connect_external/kms/`](connect_external/kms/) —
  network calls only, no kms file is used, so mycache and kms can run on **different
  machines**: set `KMS_URL` and `KMS_APPROLE_DIR` in `.env`.
