# register_to_kms.sh — sign the cache-agent up with kms

**What for:** the agent is its own component: it needs its own kms login to read its secrets.
This script creates that login — **once**.

**Who runs it:** the kms owner (needs the kms password). Re-running is safe: nothing changes.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash cache-agent/connect_external/kms/register_to_kms.sh
kms password for nishan (hidden): ********
[  OK  ] mycache-cache-agent — may read: mycache/cache-agent mycache/redis shared/anthropic · new login
[  OK  ] kv/shared/anthropic ANTHROPIC_API_KEY copied into kms from agent.conf
[  OK  ] cache-agent registered with kms — start it: bash cache-agent/host_start.sh
```

**What it does** (over the kms HTTP API):
1. logs in to kms as the owner
2. creates a **read-only policy** + an **AppRole** `mycache-cache-agent` → may read
   `kv/mycache/cache-agent` (its own) · `kv/mycache/redis` (to talk to Redis) · `kv/shared/anthropic`
3. writes `credentials/mycache-cache-agent/role_id` + `secret_id` (git-ignored, 600)
4. first time only: copies `ANTHROPIC_API_KEY` from `agent.conf` into kms if kms has none yet

**Next:** `bash cache-agent/host_start.sh`
