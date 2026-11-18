# in_container — the cache-agent's doors INSIDE the container (`sh /cache-agent/<door>.sh`)

| door (cache-agent/) | here | what |
|---|---|---|
| `health.sh` | `health.py` | ok / down — does the agent answer :$PORT/health |
| `start.sh` | `start.py` | the agent already runs (supervisor.py is the entry point): OK exit 0 · WARN exit 1 — the docker-manager-agent calls it |
| — | `container_door.py` | ccc is not mounted in the container: --help + `LOG_MIRROR_ROOT` mirror log (stamped, > 10 MB → .1), as the old POSIX sh block |

Test: `bash ~/myworkspace/projectspace/platform/mycache/cache-agent/test_agent_doors/test_agent_doors.sh` (H1 · H7)
