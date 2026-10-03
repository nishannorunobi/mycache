#!/opt/venv/bin/python
# ─────────────────────────────────────────────────────────────────────────────
# supervisor.py — the cache-agent as the container's entry point: Redis's assistant
#
# What for    Redis cannot fetch its own password or react to a changed one. The
#             agent can: it runs first, gets the secrets from kms, starts Redis as
#             its child, serves its API, and keeps both alive.
#
# Who         docker compose (mycache/docker-compose.yml "command") — always on.
#
# How         /opt/venv/bin/python /cache-agent/supervisor.py        (in the container)
#
# Steps       1. agent.conf → settings; every kms address → its value (kms.py, own login)
#             2. /run/redis.conf (RAM): requirepass; the Redis UI's copy in /mycache-secrets
#             3. start redis-server as a child (the image's docker-entrypoint → user redis)
#             4. start the agent API (uvicorn server:app :PORT) as a child — it gets the kms
#                addresses and asks kms itself per new Redis connection (rotation-proof)
#             5. watch: Redis exits → this exits too (compose restarts the container)
#                       API exits   → started again after 2 s
#                       SIGTERM     → Redis saves and stops, then the API, then exit 0
#
# Output      [agent] REDIS_PASSWORD ← kms (mycache/redis)      names only, never values
#             [agent] redis-server started (pid 12) · [agent] API started on :8892 (pid 20)
#
# Errors      kms SEALED / unreachable / no login / no access / key missing → exit 1
#             with the reason; compose restarts the container, so unsealing is enough
#
# Next        docker logs mycache-redis  ·  http://localhost:8892/health
# ─────────────────────────────────────────────────────────────────────────────
import os
import signal
import subprocess
import sys
import time

AGENT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AGENT_DIR, "connect_external", "kms"))
import kms  # noqa: E402

REDIS_CONF = "/run/redis.conf"
UI_SECRET = "/mycache-secrets/redis_password"


def say(msg):
    print(f"[agent] {msg}", file=sys.stderr, flush=True)


def usage():
    seen = False
    for line in open(__file__):
        if line.startswith("# ─"):
            if seen:
                break
            seen = True
            continue
        if seen:
            print(line[2:].rstrip())


def write_private(path, text, owner=None, mode=0o600):
    d = os.path.dirname(path)
    if not os.path.isdir(d):
        return False
    tmp = path + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)            # os.open applies the umask — set the mode explicitly
    if owner:
        import pwd
        try:
            pw = pwd.getpwnam(owner)
            os.chown(tmp, pw.pw_uid, pw.pw_gid)
        except KeyError:
            pass
    os.replace(tmp, path)
    return True


def settings():
    """agent.conf + the environment (compose env_file). Values may be kms addresses."""
    from dotenv import dotenv_values
    env = dict(os.environ)
    env.update({k: v for k, v in dotenv_values(os.path.join(AGENT_DIR, "agent.conf")).items() if v is not None})
    return env


def fetch(env):
    try:
        secrets, where = kms.resolve(env)
    except kms.KmsError as e:
        say(f"ERROR: {e}")
        sys.exit(1)
    for name in secrets:
        say(f"{name} ← kms ({where[name][len('kv/data/'):]})")
    return secrets


def start_redis(password):
    if not password:
        say("ERROR: REDIS_PASSWORD is empty — Redis is not started without a password")
        sys.exit(1)
    write_private(REDIS_CONF, f"requirepass {password}\n", owner="redis", mode=0o600)
    write_private(UI_SECRET, password, mode=0o640)
    p = subprocess.Popen(["docker-entrypoint.sh", "redis-server", REDIS_CONF, "--appendonly", "yes"], cwd="/data")
    say(f"redis-server started (pid {p.pid})")
    return p


def start_api(env, secrets):
    # The API gets the ADDRESSES (agent.conf as is), not the values: it asks kms itself,
    # per new Redis connection (redis-py CredentialProvider) — so a rotation needs no restart.
    api_env = dict(env)
    port = env.get("PORT", "8892")
    p = subprocess.Popen([sys.executable, "-m", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", port,
                          "--no-use-colors", "--access-log"], cwd=AGENT_DIR, env=api_env)
    say(f"API started on :{port} (pid {p.pid})")
    return p


def main(argv):
    if len(argv) > 1 and argv[1] in ("-h", "--help"):
        usage()
        return 0

    env = settings()
    secrets = fetch(env)           # only the kms addresses; a plain value in agent.conf stays as written
    redis_p = start_redis({**env, **secrets}.get("REDIS_PASSWORD", ""))
    api_p = start_api(env, secrets)

    stopping = {"now": False}

    def on_term(signum, frame):
        stopping["now"] = True
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)

    api_restarts = 0
    while True:
        if stopping["now"]:
            say("stopping — Redis saves and stops first")
            for p in (redis_p, api_p):
                if p.poll() is None:
                    p.terminate()
            for p in (redis_p, api_p):
                try:
                    p.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    p.kill()
            return 0
        rc = redis_p.poll()
        if rc is not None:
            say(f"ERROR: redis-server exited ({rc}) — stopping; compose restarts the container")
            if api_p.poll() is None:
                api_p.terminate()
            return rc or 1
        if api_p.poll() is not None:
            api_restarts += 1
            say(f"API exited ({api_p.returncode}) — starting it again in 2 s (restart {api_restarts})")
            time.sleep(2)
            api_p = start_api(env, secrets)
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
