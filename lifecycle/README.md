# lifecycle — what mycache's own doors do (start · stop · status · state · ensure_* · destroy · logs · login)

The doors stay at the pod's root — svcmgt (`svc_policy.conf`), Ansible, the workspace tests and you call them there.
Each door = its guide (`--help`) + one invoking line; the work is the `.py` of the same name here (rule CLAUDEWORK-332).

| door (pod root) | here | what |
|---|---|---|
| `start.sh [--no-ui]` | `start.py` | reminder · kms sign-up check · `docker compose up -d` · the summary. The pod guard stays IN the door (test_move_repos M6 runs it) |
| `stop.sh` | `stop.py` | reminder · `docker compose down` (data kept) |
| `status.sh` | `status.py` | `docker compose ps` |
| `state.sh` | `state.py` | one word for svcmgt: running / stopped (no mirror log) |
| `ensure_running.sh [--no-ui]` | `ensure_running.py` | running → OK · else network + `start.sh` + check |
| `ensure_stopped.sh` | `ensure_stopped.py` | running → `stop.sh` · else "already stopped" |
| `destroy.sh` | `destroy.py` | ⚠ type yes → `docker compose down -v` |
| `logs.sh` | `logs.py` | `docker compose logs -f --tail=100` |
| `mycache_container_login.sh [container]` | `mycache_container_login.py` | a shell inside the container (the session is not logged) |
| — | `pod.py` | what they share: the pod folder · the workspace · docker · coloured lines |

Test: `bash ~/myworkspace/projectspace/platform/mycache/lifecycle/test_lifecycle.sh` → old bash = new Python on a fake docker
(L0–L13, ALL PASS). Nothing real is touched.
