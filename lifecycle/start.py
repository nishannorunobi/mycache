#!/usr/bin/env python3
"""start.py — start mycache (Redis + the web UI): what start.sh did, step by step. The door: ../start.sh (its --help).

The pod guard (am I at my folder?) runs in the door before this — test_move_repos M6 reads it there.
"""
import os
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pod
from pod import BOLD, GREEN, OFF, RED, YELLOW, POD

if pod.starter:
    pod.starter.start()


def read_env(path):
    """KEY=VALUE lines of a file (quotes and spaces trimmed) — what `source .env` set."""
    values = {}
    for line in open(path, errors="replace"):
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_]\w*)=(.*)", line)
        if m:
            values[m.group(1)] = m.group(2).strip().strip("\"'")
    return values


def secret_mgt(agent_conf):
    """SECRET_MGT from agent.conf (the last one), lower case — '' when not set."""
    found = re.findall(r"^SECRET_MGT\s*=\s*(.*)$", open(agent_conf, errors="replace").read(), re.M) \
        if agent_conf.is_file() else []
    return found[-1].replace('"', "").replace("'", "").replace("\r", "").lower().strip() if found else ""


def master_password_filled(path):
    try:
        return path.stat().st_size > 0 and open(path, errors="replace").read().strip() != ""
    except OSError:
        return False


def signed_up_or_can():
    """kms: the cache-agent has a login · or signs itself up as it starts · or (by hand) signs up here. False = stop."""
    if secret_mgt(POD / "cache-agent/agent.conf") != "kms":
        return True                                       # SECRET_MGT=local (or not set): no kms (TESTSERVER-67)
    if list((POD / "cache-agent/connect_external/kms/credentials").glob("*/secret_id")):
        return True
    mp_dir = env.get("KMS_MASTER_PASSWORD_DIR", "")
    if mp_dir and not mp_dir.startswith("/"):
        mp_dir = f"{POD}/{mp_dir}"
    master_pw = pathlib.Path(f"{mp_dir}/master_password")
    if mp_dir and master_password_filled(master_pw):
        print(f"\033[36m[ INFO ]{OFF} the cache-agent has no kms login yet — it signs itself up as it starts "
              f"(kms's master_password is filled)", flush=True)
        return True
    if not os.environ.get("SVC_RUN") and sys.stdin.isatty():
        return pod.door("cache-agent/connect_external/kms/signup_with_kms.sh") == 0
    print(f"{RED}[ERROR]{OFF} the cache-agent is not signed up with kms yet — put your kms password into {master_pw} "
          f"(kms's master_password), then start again — or once by hand: bash {POD}/start.sh", flush=True)
    return False


os.chdir(POD)
# Reminder (CONFMGT [8.6]): the keys mycache ISSUES — near / past the rotation rule → ⚠ + what to do, else silent.
# A reminder only: never stops this program.
pod.door("cache-agent/issued_credentials/credentials_check.sh")

if not (POD / ".env").is_file():
    print(f"{RED}[ERROR]{OFF} .env not found.", flush=True)
    sys.exit(1)
env = read_env(POD / ".env")                              # Redis settings — no secret

if not signed_up_or_can():
    sys.exit(1)

with_ui = sys.argv[1:2] != ["--no-ui"]                    # --no-ui: the broker only, redis-commander stays down
print(f"{BOLD}==> Starting Redis {env.get('REDIS_VERSION', '')}...{OFF}", flush=True)
rc = pod.docker("compose", "up", "-d") if with_ui else pod.docker("compose", "up", "-d", "redis")
if rc:
    sys.exit(rc)
if not with_ui:
    print(f"{YELLOW}    Redis UI not started (--no-ui).{OFF}", flush=True)

print("")
print(f"{GREEN}{BOLD}==> Redis is up{OFF}")
print(f"    Host      : {BOLD}{env.get('REDIS_HOST', '')}:{env.get('REDIS_PORT', '')}{OFF}", flush=True)
entry = re.search(r"^REDIS_PASSWORD=.*?/v1/kv/data/(\S+)", open(POD / "cache-agent/agent.conf").read(), re.M)
if not entry:                                             # the bash stopped here too (set -e on an empty grep)
    sys.exit(1)
print(f"    Password  : {BOLD}in kms{OFF} (kv/data/{entry.group(1)} — fetched by the cache-agent)")
print(f"    Agent     : {BOLD}http://localhost:8892{OFF} (Redis's assistant — always on)")
print(f"    URL       : {BOLD}redis://:<password>@localhost:{env.get('REDIS_PORT', '')}/0{OFF}")
print("")
print(f"    {BOLD}./logs.sh{OFF}    — tail logs")
print(f"    {BOLD}./status.sh{OFF}  — container status")
print(f"    {BOLD}./stop.sh{OFF}    — stop (data preserved)")
print(f"    {BOLD}./destroy.sh{OFF} — stop + wipe all data")
