# register_to_kms.sh — sign the mycache Redis server up with kms

**What for:** mycache needs kms (its password lives there). Before mycache can read it, it must
have its own login in kms. This script creates that login — **once**.

**Who runs it:** the kms owner (needs the kms password). Re-running is safe: nothing changes.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash connect_external/kms/register_to_kms.sh
kms password for nishan (hidden): ********
[  OK  ] mycache-redis — may read: mycache/redis · new login
[  OK  ] kv/mycache/redis REDIS_PASSWORD copied into kms from .env
[  OK  ] mycache (Redis server) registered with kms — start it: bash start.sh
```
Second run: `login kept` · `already in kms`.

**What it does** (over the kms HTTP API, no kms file used):
1. logs in to kms as the owner
2. creates a **read-only policy** + an **AppRole** `mycache-redis` → may read `kv/mycache/redis` only
3. writes the login files `credentials/mycache-redis/role_id` + `secret_id` (git-ignored, 600)
4. first time only: copies `REDIS_PASSWORD` from `.env` into kms if kms has none yet

**Next:** `bash start.sh`

**Errors:** `kms … not running + unsealed` → unseal kms (startup prompt / http://127.0.0.1:8110/ui) ·
`login failed` → wrong kms password (forgot it: kms `forget_ui_login_password.sh`).
