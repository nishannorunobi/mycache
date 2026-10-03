# mycache

Redis cache for the workspace (Plane uses it) + **redis-commander** (web UI, :8081) +
**cache-agent** (:8892) — the container's **entry point**, Redis's assistant: it fetches the
password from kms, runs Redis as its child, keeps a rotated password live, and answers on :8892.

```
bash start.sh [--no-ui]   # start Redis + its agent (+ UI)     bash stop.sh    # stop all (data kept)
bash status.sh            # containers                         bash logs.sh    # tail logs
bash cache-agent/host_status.sh                                 # the agent (it runs with Redis)
```

## 🔑 Where are the secrets?

**Not in any file of this project.** They live in **kms** (the workspace's key management
system, OpenBao). The **cache-agent is the container's entry point — Redis's assistant**: it
fetches the secrets with its own kms login, starts Redis with the password, serves its API
on :8892 and keeps both alive. In `cache-agent/agent.conf` a secret's value is **its kms address**:

```
ANTHROPIC_API_KEY=http://kms-openbao:8200/v1/kv/data/shared/anthropic
REDIS_PASSWORD=http://kms-openbao:8200/v1/kv/data/mycache/redis
```

```
docker compose up → mycache-redis container
  └─ cache-agent/supervisor.py
       kms ──▶ REDIS_PASSWORD, ANTHROPIC_API_KEY   (own login: connect_external/kms/credentials/)
       └─ redis-server (child, password in RAM)  ·  agent API :8892  ·  Redis UI ← RAM volume
```

| Secret | Used by | Where it lives | Fetched by |
|---|---|---|---|
| `REDIS_PASSWORD` | Redis server, redis-commander, cache-agent | kms `kv/mycache/redis` | the cache-agent (`supervisor.py` → `connect_external/kms/kms.py`) |
| `ANTHROPIC_API_KEY` | cache-agent | kms `kv/shared/anthropic` | the same |

- `.env` holds the Redis settings (version, host, port, TZ) — no secret. `cache-agent/agent.conf`
  holds the agent's settings and the kms addresses. Both are in git on purpose. A plain value
  instead of an address also works (a quick test without kms) — never commit that; `test_kms.sh` checks it.
- **New secret?** `bash cache-agent/connect_external/kms/add_new_secret_to_kms.sh` — it asks the
  name and the value, stores the value in kms and writes the `agent.conf` line for you. Then restart.
- **See / change a secret:** kms UI http://127.0.0.1:8110/ui → Method *Username* (owner
  login) → *Secrets engines* → `kv` → `mycache` → `redis`. After a change: `bash stop.sh && bash start.sh`.
- **Connecting by hand** (redis-cli): `REDISCLI_AUTH=<password> redis-cli -h 127.0.0.1 ping` —
  never `-a <password>` (it shows in the process list).
- **kms sealed** → the container stops with *"kms is SEALED"* (`docker logs mycache-redis`, the
  `[agent]` lines): unseal it (startup prompt or the kms UI) — it retries by itself. A running Redis keeps working.
- **First time:** the agent signs itself up with kms (once, asks the kms owner's password):
  `bash start.sh` by hand does it (or `bash cache-agent/connect_external/kms/signup_with_kms.sh`).
- **Every script explains itself:** `bash <script> --help` (or read its header).
- How mycache talks to kms: [`cache-agent/connect_external/kms/`](cache-agent/connect_external/kms/) —
  the only kms folder; network calls only, no kms file is used, so mycache and kms can run on
  **different machines**: put that kms's address in the `agent.conf` lines (`https://<kms-host>:<port>/v1/kv/data/…`).
- **Image:** mycache runs its own image `mycache-redis` (Redis + Python, `dockerspace/Dockerfile`) —
  built once by `start.sh` (needs the internet once), then offline.
