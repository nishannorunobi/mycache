#!/opt/venv/bin/python
# ─────────────────────────────────────────────────────────────────────────────
# fetch_from_kms.py — inside the container: fill in every secret from kms, then start the program
#
# What for    .env holds no secret — a secret's value is its kms address:
#               REDIS_PASSWORD=http://kms-openbao:8200/v1/kv/data/mycache/redis
#             This replaces each such value with the real one, then starts the program.
#
# Who         The container itself, first thing at start (docker-compose.yml "command").
#
# How         fetch_from_kms.py <program> [args…]
#             e.g. fetch_from_kms.py sh -c 'exec redis-server …'
#
# Steps       1. every env value with /v1/kv/ in it is a kms address
#             2. log in with this component's login files (credentials/<login>/ — one login)
#             3. read each address; the key inside = the env name (REDIS_PASSWORD)
#             4. throw the 1-hour pass away, start the program with the filled-in env
#
# Output      [kms] REDIS_PASSWORD ← kms (kv/data/mycache/redis)     names only, never values
#
# Errors      kms SEALED / unreachable   → exit 1: unseal kms (the container restarts by itself)
#             no login files             → exit 1: on the host, bash start.sh by hand (signs up once)
#             login refused / no access  → exit 1: wrong or revoked login, or path not allowed
#             key missing in kms         → exit 1: bash connect_external/kms/add_new_secret_to_kms.sh
#
# Next        nothing — the program runs with its secrets in memory only
# ─────────────────────────────────────────────────────────────────────────────
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CRED = os.environ.get("KMS_CREDENTIALS_DIR") or os.path.join(HERE, "credentials")   # test switch only
KMS_ADDR = re.compile(r"^(https?://[^/]+)(/v1/kv/.+)$")


def usage():
    for line in open(__file__):
        if line.startswith("# ─") and usage.seen:
            break
        if line.startswith("# ─"):
            usage.seen = True
            continue
        if usage.seen:
            print(line[2:].rstrip())


usage.seen = False


def die(msg):
    print(f"[kms] ERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(1)


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        usage()
        return 0 if len(argv) > 1 else 2

    wanted = {k: KMS_ADDR.match(v) for k, v in os.environ.items() if KMS_ADDR.match(v or "")}
    if wanted:
        import hvac
        import requests

        bases = {m.group(1) for m in wanted.values()}
        if len(bases) != 1:
            die("all kms addresses must point to the same kms: " + ", ".join(sorted(bases)))
        base = bases.pop()

        try:
            h = requests.get(base + "/v1/sys/health", timeout=5).status_code
        except requests.RequestException:
            die(f"kms is not reachable at {base}")
        if h == 503:
            die("kms is SEALED — unseal it; this container restarts by itself")
        if h not in (200, 429, 472, 473):
            die(f"kms at {base} is not ready (health {h})")

        logins = sorted(d for d in os.listdir(CRED) if os.path.isdir(os.path.join(CRED, d))) if os.path.isdir(CRED) else []
        if len(logins) != 1:
            die(f"need exactly one kms login in {CRED} (found {len(logins)}) — on the host run start.sh by hand once")
        d = os.path.join(CRED, logins[0])
        try:
            role_id = open(os.path.join(d, "role_id")).read().strip()
            secret_id = open(os.path.join(d, "secret_id")).read().strip()
        except OSError:
            die(f"login files missing in {d} — on the host run start.sh by hand once")

        client = hvac.Client(url=base)
        try:
            client.auth.approle.login(role_id=role_id, secret_id=secret_id)
        except Exception:
            die(f"kms refused the login as {logins[0]} (wrong / revoked login, or not from an allowed address)")
        del role_id, secret_id

        cache = {}
        try:
            for name, m in sorted(wanted.items()):
                path = m.group(2)
                if path not in cache:
                    try:
                        cache[path] = (client.adapter.get(path) or {}).get("data", {}).get("data") or {}
                    except Exception:
                        die(f"{name}: {logins[0]} may not read {path[4:]}, or it does not exist")
                if name not in cache[path]:
                    die(f"{name}: no key {name} in {path[4:]} — add it: bash connect_external/kms/add_new_secret_to_kms.sh")
                os.environ[name] = cache[path][name]
                print(f"[kms] {name} ← kms ({path[4:]})", file=sys.stderr, flush=True)
        finally:
            try:
                client.auth.token.revoke_self()
            except Exception:
                pass
            cache.clear()

    os.execvp(argv[1], argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
