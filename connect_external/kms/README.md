# connect_external/kms — mycache ↔ kms

`kms_secrets.sh` (sourced) gives `kms_get <approle> <kv path> <KEY>…`: the values are exported,
kept in memory, never printed. kms sealed / down / no access → clear error, the start stops.

## API contract mycache relies on (kms `http://127.0.0.1:8110`)

| Call | Sends | Gets |
|---|---|---|
| `GET /v1/sys/health` | — | 200 unsealed · 503 sealed · 501 not initialised |
| `POST /v1/auth/approle/login` | `{"role_id","secret_id"}` (body, stdin) | `auth.client_token` (1 h) |
| `GET /v1/kv/data/<path>` | header `X-Vault-Token` (via fd) | `data.data.{KEY: value}` |
| `POST /v1/auth/token/revoke-self` | header `X-Vault-Token` | token thrown away |

| mycache part | AppRole | kv path | Key |
|---|---|---|---|
| Redis (`start.sh`) | `mycache-redis` | `mycache/redis` | `REDIS_PASSWORD` |
| cache-agent (`cache-agent/host_start.sh`) | `mycache-cache-agent` | `shared/anthropic` | `ANTHROPIC_API_KEY` |

Login files: `<workspace>/mountspace/secrets/kms/approle/<approle>/{role_id,secret_id}` (700/600),
written once by the owner when mycache was added to kms. Override: `KMS_APPROLE_DIR`, `KMS_URL`.
