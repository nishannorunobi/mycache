# cache-agent/connect_external — how the cache-agent talks to other components

The cache-agent is its own component (not the Redis server), so it has its own connections.
Everything here talks over the **network (APIs)** — no file of another project or of the Redis server.

| Folder | Component | How | Used by |
|---|---|---|---|
| `kms/` | kms (OpenBao) — secrets | HTTP API `http://127.0.0.1:8110` · sign up once: `register_to_kms.sh` | `host_start.sh` (ANTHROPIC_API_KEY, REDIS_PASSWORD) |
