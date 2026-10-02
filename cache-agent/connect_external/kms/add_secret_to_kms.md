# add_secret_to_kms.sh — a NEW secret for the cache-agent → kms

**What for:** a new password / key / token for the agent goes into **kms**, never into `agent.conf`.

**Who runs it:** the kms owner (needs the kms password). The agent itself may only read.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash cache-agent/connect_external/kms/add_secret_to_kms.sh NEW_AGENT_KEY
kms password for nishan (hidden): ********
Value for NEW_AGENT_KEY (hidden): ********
[  OK  ] kv/mycache/cache-agent  NEW_AGENT_KEY stored (version 1) — read it with: kms_get mycache-cache-agent mycache/cache-agent NEW_AGENT_KEY
```

**What it does:** stores the value in `kv/mycache/cache-agent` (the agent's own place); keys
already there are kept; nothing is printed except the version number. Shared keys
(`kv/shared/…`) are not the agent's own and are not written here.

**Next — use it in the code**, in `cache-agent/host_start.sh`:
```bash
kms_get mycache-cache-agent mycache/cache-agent NEW_AGENT_KEY || exit 1
```
and hand it to the agent by name: `docker exec -e NEW_AGENT_KEY …`
