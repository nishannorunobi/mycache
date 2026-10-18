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
# Steps       0. no kms login yet → signs itself up: the owner's kms password from kms's master_password (read-only
#                mount, KMS_MASTER_PASSWORD_FILE) → its own connect_external/kms/signup_with_kms.sh (KMS_TOKEN)
#             1. agent.conf → settings; every kms address → its value (kms.py, own login) — a key kms does not have →
#                connect_external/kms/register_kms_keys_when_missing_with_random_initial.sh (owner login from
#                master_password): created with an initial random value (an outside key: a placeholder), fetched again
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
import re
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


CRED_DIR = os.path.join(AGENT_DIR, "connect_external", "kms", "credentials")


def owner_login(env, by_hand):
    """The owner's kms login for a one-off write (sign-up / register): the password from kms's master_password folder,
    mounted READ-ONLY (KMS_MASTER_PASSWORD_FILE, KMS-215). Empty / missing → one line naming the file + the by-hand
    command, exit 1. Returns (kms base URL, token, True). The password is never printed or logged."""
    import json, urllib.request
    pw_file = os.environ.get("KMS_MASTER_PASSWORD_FILE", "")
    host_hint = "mountspace/usb/myworkspace/projectspace/kms/master_password/master_password (on the PC)"
    pw = ""
    if pw_file and os.path.isfile(pw_file):
        with open(pw_file) as f:
            pw = f.readline().rstrip("\r\n")
    if not pw.strip():
        why = "not mounted" if not pw_file or not os.path.isfile(pw_file) else "empty"
        say(f"ERROR: kms's master_password is {why} — put your kms password into {host_hint}, then start again"
            f" (or by hand on the PC: {by_hand})")
        sys.exit(1)
    base = next((v.split("/v1/")[0] for v in env.values() if kms.is_address(v)), "")
    if not base:
        say("ERROR: agent.conf names no kms address")
        sys.exit(1)
    owner = os.environ.get("KMS_OWNER", "nishan")
    try:
        req = urllib.request.Request(f"{base}/v1/auth/userpass/login/{owner}", data=json.dumps({"password": pw}).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=10) as r:
            token = json.load(r)["auth"]["client_token"]
    except Exception as e:
        del pw
        say(f"ERROR: kms refused the login with the password from master_password ({type(e).__name__}) — check {host_hint}")
        sys.exit(1)
    del pw
    return base, token, True


def revoke(base, token):
    import urllib.request
    try:                                          # the login is not needed any more
        urllib.request.urlopen(urllib.request.Request(f"{base}/v1/auth/token/revoke-self", data=b"{}",
                               headers={"X-Vault-Token": token}, method="POST"), timeout=10).close()
    except Exception:
        pass


def run_kms_script(name, base, token, args=()):
    """connect_external/kms/<name> with the owner login handed over (KMS_TOKEN) — its lines shown indented."""
    child = dict(os.environ)                      # settings like KMS_ALLOWED_CIDRS pass through; the login + address are set here
    child.update({"KMS_TOKEN": token, "KMS_URL": base})
    r = subprocess.run(["bash", os.path.join(AGENT_DIR, "connect_external", "kms", name), *args],
                       env=child, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    del child
    for line in (r.stdout + r.stderr).splitlines():
        if line.strip() and "[logging]" not in line:
            say("  " + re.sub(r"\x1b\[[0-9;]*m", "", line))
    return r.returncode


def ensure_login(env):
    """No kms login yet → the agent signs itself up (TESTSERVER-46): it reads the owner's kms password from kms's
    master_password folder, mounted READ-ONLY (KMS_MASTER_PASSWORD_FILE, KMS-215), logs in to kms itself and runs its
    own connect_external/kms/signup_with_kms.sh with that login. The new login files get the agent folder's owner
    (this container runs as root). Already signed up → nothing. The password is never printed or logged."""
    import glob
    if glob.glob(os.path.join(CRED_DIR, "*", "secret_id")):
        return
    owner = os.environ.get("KMS_OWNER", "nishan")
    say(f"no kms login yet — signing up with kms as {owner}, password from kms's master_password")
    base, token, _ = owner_login(env, "bash start.sh (asks your kms password)")
    rc = run_kms_script("signup_with_kms.sh", base, token)
    revoke(base, token)
    del token
    if rc != 0 or not glob.glob(os.path.join(CRED_DIR, "*", "secret_id")):
        say("ERROR: the kms sign-up failed — the lines above say why")
        sys.exit(1)
    st = os.stat(AGENT_DIR)                       # the host user who owns the project folder
    for root, dirs, files in os.walk(CRED_DIR):
        for n in [root] + [os.path.join(root, x) for x in dirs + files]:
            os.chown(n, st.st_uid, st.st_gid)
    say("signed up with kms — login saved in connect_external/kms/credentials/ (600)")


MISSING = (" is not in kms", "no key ")             # kms.py's words for a key kms does not have (a 403 "may not read" is not)


def fetch(env):
    """Every kms address → its value. A key kms does not have → registered once with an initial random value
    (connect_external/kms/register_kms_keys_when_missing_with_random_initial.sh, owner rule 2026-10-17), then fetched
    again — a fresh kms never stops Redis. A placeholder (an outside key) is named once: its feature is off."""
    try:
        secrets, where = kms.resolve(env)
    except kms.KmsError as e:
        if not any(m in str(e) for m in MISSING):
            say(f"ERROR: {e}")
            sys.exit(1)
        missing = []
        for name in sorted(k for k, v in env.items() if kms.is_address(v)):
            try:
                kms.resolve({name: env[name]}, fresh=True)
            except kms.KmsError as e1:
                if not any(m in str(e1) for m in MISSING):
                    say(f"ERROR: {e1}")
                    sys.exit(1)
                missing.append(name)
        say(f"{', '.join(missing)}: not in kms — registering with an initial random value")
        base, token, mine = owner_login(env, f"bash connect_external/kms/register_kms_keys_when_missing_with_random_initial.sh {' '.join(missing)}")
        rc = run_kms_script("register_kms_keys_when_missing_with_random_initial.sh", base, token, missing)
        if mine:
            revoke(base, token)
        del token
        if rc != 0:
            say("ERROR: registering the missing keys failed — the lines above say why")
            sys.exit(1)
        try:
            secrets, where = kms.resolve(env, fresh=True)
        except kms.KmsError as e2:
            say(f"ERROR: {e2}")
            sys.exit(1)
    for name in secrets:
        flag = "   ⚠ placeholder — its feature is off until you set the real value in kms" if str(secrets[name]).startswith("placeholder-") else ""
        say(f"{name} ← kms ({where[name][len('kv/data/'):]}){flag}")
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
    ensure_login(env)              # no kms login yet → signs itself up (TESTSERVER-24)
    secrets = fetch(env)           # only the kms addresses; a plain value in agent.conf stays as written
    current = {**env, **secrets}.get("REDIS_PASSWORD", "")
    redis_p = start_redis(current)
    api_p = start_api(env, secrets)
    del secrets

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
            api_p = start_api(env, {})
        time.sleep(1)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
