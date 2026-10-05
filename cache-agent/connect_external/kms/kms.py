#!/opt/venv/bin/python
# ─────────────────────────────────────────────────────────────────────────────
# kms.py — the cache-agent's kms client (OpenBao, via hvac). Imported, not run.
#
# What for    agent.conf holds no secret — a secret's value is its kms address:
#               REDIS_PASSWORD=http://kms-openbao:8200/v1/kv/data/mycache/redis
#             This module turns such addresses into the real values, with the
#             agent's own kms login (credentials/<login>/ — exactly one).
#
# Who         supervisor.py (at start) · server.py (its own Redis connections: redis-py
#             CredentialProvider — a refused password → one fresh read, then retry)
#
# How         import kms
#             secrets, where = kms.resolve(env)      # {NAME: value}, {NAME: "kv/data/…"}
#             kms.read("http://…/v1/kv/data/mycache/redis")["REDIS_PASSWORD"]
#
# Steps       1. a value with /v1/kv/ in it is a kms address (base + entry)
#             2. health: sealed / unreachable → KmsError with the reason
#             3. log in (role_id + secret_id → 1-hour pass), read the entry, keep it
#                (read again only when asked: fresh=True, e.g. after Redis refused the password)
#             4. the key inside the entry = the env name
#
# Output      nothing printed here — callers print names only, never values
#
# Errors      KmsError("kms is SEALED — …") · KmsError("no login files …") ·
#             KmsError("… may not read …") · KmsError("no key NAME in …")
#
# Next        bash connect_external/kms/signup_with_kms.sh (once) ·
#             bash connect_external/kms/add_new_secret_to_kms.sh (a new secret)
# ─────────────────────────────────────────────────────────────────────────────
import os
import re
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
CRED = os.environ.get("KMS_CREDENTIALS_DIR") or os.path.join(HERE, "credentials")   # test switch only
ADDRESS = re.compile(r"^(https?://[^/]+)/v1/(kv/[^#\s]+)(?:#([A-Za-z_][A-Za-z0-9_]*))?$")   # …/<entry>[#KEY]: the entry names it differently


class KmsError(Exception):
    """Something the owner must fix — the message says what."""


def is_address(value):
    return bool(value) and bool(ADDRESS.match(value))


def _login_dir():
    logins = sorted(d for d in os.listdir(CRED) if os.path.isdir(os.path.join(CRED, d))) if os.path.isdir(CRED) else []
    if len(logins) != 1:
        raise KmsError(f"need exactly one kms login in {CRED} (found {len(logins)}) — on the host: bash cache-agent/connect_external/kms/signup_with_kms.sh")
    return logins[0], os.path.join(CRED, logins[0])


class _Client:
    """One kms (base URL): health, login, cached reads. Thread-safe."""

    def __init__(self, base):
        self.base = base
        self._client = None
        self._cache = {}          # api path → (time, data)
        self._lock = threading.Lock()

    def _health(self):
        import requests
        try:
            code = requests.get(self.base + "/v1/sys/health", timeout=5).status_code
        except requests.RequestException:
            raise KmsError(f"kms is not reachable at {self.base}")
        if code == 503:
            raise KmsError("kms is SEALED — unseal it (startup prompt or the kms UI)")
        if code not in (200, 429, 472, 473):
            raise KmsError(f"kms at {self.base} is not ready (health {code})")

    def _login(self):
        import hvac
        name, d = _login_dir()
        try:
            role_id = open(os.path.join(d, "role_id")).read().strip()
            secret_id = open(os.path.join(d, "secret_id")).read().strip()
        except OSError:
            raise KmsError(f"login files missing in {d} — on the host: bash cache-agent/connect_external/kms/signup_with_kms.sh")
        c = hvac.Client(url=self.base)
        try:
            c.auth.approle.login(role_id=role_id, secret_id=secret_id)
        except Exception:
            raise KmsError(f"kms refused the login as {name} (wrong / revoked login, or not from an allowed address)")
        finally:
            del role_id, secret_id
        self._client = c
        self.login_name = name

    def read(self, api_path, fresh=False):
        """api_path like 'kv/data/mycache/redis' → the entry's keys (kept until fresh=True)."""
        with self._lock:
            hit = self._cache.get(api_path)
            if hit and not fresh:
                return dict(hit[1])
            self._health()
            if self._client is None:
                self._login()
            data = None
            for attempt in (1, 2):
                try:
                    data = (self._client.adapter.get("/v1/" + api_path) or {}).get("data", {}).get("data")
                    break
                except Exception:
                    if attempt == 1:
                        self._login()          # the 1-hour pass may have expired → one new login, one retry
                        continue
                    raise KmsError(f"{getattr(self, 'login_name', 'this login')} may not read {api_path[len('kv/data/'):]}, or it does not exist")
            if not isinstance(data, dict):
                raise KmsError(f"{api_path[len('kv/data/'):]} is empty in kms")
            self._cache[api_path] = (True, data)
            return dict(data)


_clients = {}
_clients_lock = threading.Lock()


def client_for(base):
    with _clients_lock:
        if base not in _clients:
            _clients[base] = _Client(base)
        return _clients[base]


def read(address, fresh=False):
    """The entry behind a kms address (http://host/v1/kv/data/x) → {key: value}."""
    m = ADDRESS.match(address or "")
    if not m:
        raise KmsError(f"not a kms address: {address}")
    return client_for(m.group(1)).read(m.group(2), fresh=fresh)


def resolve(env, fresh=False):
    """Every kms address in env → its value. Returns ({NAME: value}, {NAME: 'kv/data/…'})."""
    secrets, where = {}, {}
    for name in sorted(env):
        m = ADDRESS.match(env[name] or "")
        if not m:
            continue
        key = m.group(3) or name                  # KEY=…/<entry>#OTHER_KEY → that key inside the entry
        entry = read(env[name], fresh=fresh)
        if key not in entry:
            raise KmsError(f"no key {key} in {m.group(2)[len('kv/data/'):]} — add it: bash cache-agent/connect_external/kms/add_new_secret_to_kms.sh")
        secrets[name] = entry[key]
        where[name] = m.group(2) + (f"#{key}" if m.group(3) else "")
    return secrets, where


if __name__ == "__main__":          # not a program: --help prints the header, anything else says so
    import sys
    seen = False
    for line in open(__file__):
        if line.startswith("# ─"):
            if seen:
                break
            seen = True
            continue
        if seen:
            print(line[2:].rstrip())
    sys.exit(0 if sys.argv[1:] in (["-h"], ["--help"]) else 2)
