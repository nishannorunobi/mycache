# host_lifecycle — the cache-agent's doors on the HOST (svcmgt calls them: svc_policy.conf)

| door (cache-agent/) | here | what |
|---|---|---|
| `host_start.sh` | `host_start.py` | answers :8892 → nothing · container down → `../start.sh --no-ui` · wait until it answers |
| `host_status.sh [--state]` | `host_status.py` | answers :8892? human line · `--state` = running / stopped |
| `host_stop.sh` | `host_stop.py` | says so: the agent stops only with Redis (`bash ../stop.sh`) — a no-op for svcmgt |
| — | `agent_door.py` | what they share: `CACHE_AGENT_URL` (default http://localhost:8892) · --help · the mirror log (next to the container's root-owned folder when needed) |

Test: `bash ~/myworkspace/projectspace/platform/mycache/cache-agent/test_agent_doors/test_agent_doors.sh` (H0–H7)
