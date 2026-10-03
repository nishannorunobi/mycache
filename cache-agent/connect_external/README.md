# cache-agent/connect_external — how the cache-agent talks to other components

The cache-agent is its own component (not the Redis server), so it has its own connections.
Everything here talks over the **network (APIs)** — no file of another project or of the Redis server.

| Folder | Component | How | Used by |
|---|---|---|---|
| `kms/` | kms (OpenBao) — secrets | HTTP API (the address is in each `agent.conf` value) · sign up once: `signup_with_kms.sh` (or `../start.sh` by hand) | `kms.py`: `supervisor.py` at start + every 60 s (rotation), `server.py` per Redis connection |
