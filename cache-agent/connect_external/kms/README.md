# cache-agent/connect_external/kms — cache-agent ↔ kms

```
cache-agent/connect_external/kms/
├── register_to_kms.sh   sign the agent up with kms — ONCE (asks the kms owner's password)
├── add_secret_to_kms.sh a NEW agent secret → kms (never agent.conf): add_secret_to_kms.sh <KEY>
├── kms_secrets.sh       the client host_start.sh uses at every start (kms_get)
├── credentials/         the agent's login files (git-ignored, 700/600)
└── README.md
```

## 1. Register (once)

`bash cache-agent/connect_external/kms/register_to_kms.sh`

| AppRole | may read | why |
|---|---|---|
| `mycache-cache-agent` | `kv/mycache/cache-agent` | its own secrets (none yet) |
| | `kv/mycache/redis` | REDIS_PASSWORD — to talk to Redis |
| | `kv/shared/anthropic` | ANTHROPIC_API_KEY — shared by the agents |

First time only: copies `ANTHROPIC_API_KEY` from `agent.conf` into kms if kms has none yet.

## 2. Every start

`host_start.sh` → `kms_get` (health → AppRole login → read → token revoked) → hands both values to
the agent by NAME (`docker exec -e ANTHROPIC_API_KEY -e REDIS_PASSWORD …`) — never on a command line.
kms sealed / down → the start stops with a clear error.

## Settings (`agent.conf`, not secret)

| Setting | Default | Other machine / environment |
|---|---|---|
| `KMS_URL` | `http://127.0.0.1:8110` | `http://<kms-host>:<port>` (test) · `https://…` (prod) |
| `KMS_APPROLE_DIR` | `connect_external/kms/credentials` | another folder with the login files |
