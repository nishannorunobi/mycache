# connect_external/kms — mycache ↔ kms

mycache **needs** kms (its secrets live there); kms does not need mycache. Everything here talks
to kms over its **HTTP API** — no kms file is used, so mycache and kms can run on different machines.

```
connect_external/kms/
├── register_to_kms.sh   sign mycache up with kms — ONCE (asks the kms owner's password)
├── kms_secrets.sh       the client start.sh / cache-agent use at every start (kms_get)
├── credentials/         mycache's login files, written by register (git-ignored, 700/600)
└── README.md
```

## 1. Register (once)

```
bash connect_external/kms/register_to_kms.sh
```
1. logs in to kms as the owner (password hidden)
2. creates, per mycache part, a **read-only policy** + an **AppRole** (a login for machines):

   | AppRole | may read | used by |
   |---|---|---|
   | `mycache-redis` | `kv/mycache/redis` | `start.sh` → REDIS_PASSWORD |
   | `mycache-cache-agent` | `kv/mycache/cache-agent`, `kv/shared/anthropic` | `cache-agent/host_start.sh` → ANTHROPIC_API_KEY |
3. writes `credentials/<approle>/{role_id,secret_id}` (like a username + password)
4. first time only: copies `REDIS_PASSWORD` (from `.env`) and `ANTHROPIC_API_KEY` (from
   `cache-agent/agent.conf`) into kms if kms has none yet. Re-running changes nothing.

## 2. Every start — the API contract

| Call | Sends | Gets |
|---|---|---|
| `GET /v1/sys/health` | — | 200 unsealed · 503 sealed · 501 not initialised |
| `POST /v1/auth/approle/login` | `{"role_id","secret_id"}` (body, stdin) | `auth.client_token` (1 h) |
| `GET /v1/kv/data/<path>` | header `X-Vault-Token` (via fd) | `data.data.{KEY: value}` |
| `POST /v1/auth/token/revoke-self` | header `X-Vault-Token` | token thrown away |

kms sealed / down / no access → a clear error and the start stops (no fallback to a file).

## Settings (mycache's `.env`)

| Setting | Default | Other machine / environment |
|---|---|---|
| `KMS_URL` | `http://127.0.0.1:8110` | `http://<kms-host>:<port>` (test) · `https://…` (prod) |
| `KMS_APPROLE_DIR` | `connect_external/kms/credentials` | another folder with the login files |
