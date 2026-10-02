# kms_secrets.sh — how the mycache Redis server reads its secrets from kms

**What for:** `start.sh` loads it and calls `kms_get` to get `REDIS_PASSWORD` at every start —
kept in memory, never printed, never in a file. You do **not** run it yourself.

**Used like this** (start.sh):
```bash
source "$SCRIPT_DIR/connect_external/kms/kms_secrets.sh"
kms_get mycache-redis mycache/redis REDIS_PASSWORD || exit 1
```

**What it does** — 4 network calls to kms (the API contract; no kms file is used):

| Call | Sends | Gets |
|---|---|---|
| `GET /v1/sys/health` | — | 200 unsealed · 503 sealed · 501 not initialised |
| `POST /v1/auth/approle/login` | role_id + secret_id (from `credentials/`) | a 1-hour token |
| `GET /v1/kv/data/mycache/redis` | the token | `{REDIS_PASSWORD: …}` |
| `POST /v1/auth/token/revoke-self` | the token | token thrown away |

**When it fails** the start stops (no fallback to a file):
`kms is SEALED` → unseal kms · `no kms login files` → run `register_to_kms.sh` ·
`may not read` → wrong path · `not reachable` → kms down or wrong `KMS_URL`.

**Settings** (mycache `.env`, not secret — mycache and kms may run on different machines):

| Setting | Default | Other machine / environment |
|---|---|---|
| `KMS_URL` | `http://127.0.0.1:8110` | `http://<kms-host>:<port>` (test) · `https://…` (prod) |
| `KMS_APPROLE_DIR` | `connect_external/kms/credentials` | another folder with the login files |
