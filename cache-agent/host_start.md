# host_start.sh — Start the cache-agent (AI helper, :8892) inside the mycache-redis container — from the host.

**Who runs it:** You (not started by default at startup).

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash cache-agent/host_start.sh
[OK] Cache agent running on :8892
```

**What it does:**
1. already answering → nothing to do
2. gets `ANTHROPIC_API_KEY` + `REDIS_PASSWORD` from **kms** with the agent's own login (`connect_external/kms/kms_secrets.sh`)
3. builds the agent's venv if missing, then starts it via `docker exec -e …` (values by name, never on a command line)

**Next / errors:** Needs mycache running (`bash start.sh`) and the agent registered once: `bash cache-agent/connect_external/kms/register_to_kms.sh`.
