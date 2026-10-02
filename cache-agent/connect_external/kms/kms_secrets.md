# kms_secrets.sh — how the cache-agent reads its secrets from kms

**What for:** `host_start.sh` loads it and calls `kms_get` for `ANTHROPIC_API_KEY` and
`REDIS_PASSWORD` at every start, with the agent's own login — in memory only, handed to the agent
by name (`docker exec -e …`). You do **not** run it yourself.

**Used like this** (host_start.sh):
```bash
source "$SCRIPT_DIR/connect_external/kms/kms_secrets.sh"
kms_get mycache-cache-agent shared/anthropic ANTHROPIC_API_KEY || exit 1
kms_get mycache-cache-agent mycache/redis REDIS_PASSWORD || exit 1
```

**What it does** — the same 4 network calls as the Redis server's client: health → AppRole login
(1-hour token) → read → token revoked. kms sealed / down / no access → the start stops.

**Settings** (`agent.conf`, not secret): `KMS_URL` (default `http://127.0.0.1:8110`; test http, prod
https) · `KMS_APPROLE_DIR` (default `connect_external/kms/credentials`).
