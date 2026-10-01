# connect_external — how mycache talks to other components

One folder per external component mycache needs. Everything here talks to that component
over the **network (its API)** — mycache never uses a file of another project.

| Folder | Component | How | Used by |
|---|---|---|---|
| `kms/` | kms (OpenBao) — secrets | HTTP API `http://127.0.0.1:8110` | `start.sh` (REDIS_PASSWORD), `cache-agent/host_start.sh` (ANTHROPIC_API_KEY) |

Add a new component: `connect_external/<component>/` with its client + a README of the API
contract it relies on.
