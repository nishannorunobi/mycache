# connect_external — how mycache talks to other components

One folder per external component mycache needs. Everything here talks to that component
over the **network (its API)** — mycache never uses a file of another project.

| Folder | Component | How | Used by |
|---|---|---|---|
| `kms/` | kms (OpenBao) — secrets | HTTP API `http://127.0.0.1:8110` · sign up once: `register_to_kms.sh` | `start.sh` (REDIS_PASSWORD) |

The cache-agent is a separate component and keeps its own: `cache-agent/connect_external/`.

Add a new component: `connect_external/<component>/` with everything for it — registration
(e.g. `register_to_<component>.sh`), the client, its credentials (git-ignored) and a README of
the API contract.
