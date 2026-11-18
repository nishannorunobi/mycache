#!/usr/bin/env python3
"""test_lifecycle.py — mycache's lifecycle doors (start · stop · status · state · ensure_* · destroy · logs · login)
against a FAKE docker, the old bash and the new Python side by side. The door: test_lifecycle.sh (its --help).

    L0  every door: clean (invoking lines only) · --help shows its guide · every .py compiles
    L1  state: running / stopped                                  ┐
    L2  status: compose ps, its exit code                         │
    L3  start: the full output · --no-ui · compose fails → its code│ each run on the OLD bash (git OLD_REF) and the
    L4  start: kms not signed up — master_password filled → INFO · │ NEW door + .py in two throwaway pods:
        empty, by a script → ERROR exit 1                          │ the same lines · exit code · docker calls
    L5  start: .env missing → ERROR exit 1                         │
    L6  stop · L7 ensure_running (running · not → network + start) │
    L8  ensure_stopped · L9 destroy (no · yes · no input) · L10 logs│
    L11 login refuses: unknown container · docker down · not running · no terminal
    L12 the reminder (credentials_check) shows in start / stop and never stops them   ┘
    L13 start's pod guard: one level too high → refuses, exit 1, nothing started (old and new)

Nothing real: throwaway pods in a temp folder (no credentials/ copied), a fake docker first on PATH.
OLD_REF = the last bash version (git) — not found (a copy without git) → only the new side runs.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in pathlib.Path(__file__).resolve().parents
                if (p / "mountspace").is_dir()][:1]
try:
    import starter
    starter.start()
except ImportError:
    starter = None

HERE = pathlib.Path(__file__).resolve().parent
POD = HERE.parent
OLD_REF = os.environ.get("OLD_REF", "709477f")            # mycache's main before the conversion (CLAUDEWORK-454)
DOORS = ["start", "stop", "status", "state", "ensure_running", "ensure_stopped", "destroy", "logs",
         "mycache_container_login"]
FAILED = []

FAKE_DOCKER = r'''#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(" ".join(a) + "\n")
st = os.environ["FAKE_STATE"]
names = open(st).read().split() if os.path.exists(st) else []
def save(n): open(st, "w").write("\n".join(n) + "\n")
if a[:1] == ["info"]:
    sys.exit(1 if os.environ.get("FAKE_DOCKER_DOWN") else 0)
if a[:1] == ["ps"]:
    if "-q" in a:
        want = a[a.index("-f") + 1].split("=", 1)[1].strip("^$")
        print("c0ffee" if want in names else "", end="\n" if want in names else "")
    else:
        print("\n".join(names + ([] if "status=running" in a else os.environ.get("FAKE_RESTARTING", "").split())))
    sys.exit(0)
if a[:2] == ["network", "inspect"]:
    sys.exit(1 if os.environ.get("FAKE_NET_MISSING") else 0)
if a[:1] == ["compose"]:
    rc = int(os.environ.get("FAKE_COMPOSE_RC", "0"))
    print("fake compose " + " ".join(a[1:]))
    if rc == 0 and a[1:2] == ["up"] and not os.environ.get("FAKE_UP_FAILS"):
        save(sorted(set(names + ["mycache-redis"] + ([] if "redis" in a else ["mycache-redis-ui"]))))
    if rc == 0 and a[1:2] == ["down"]:
        save([])
    sys.exit(rc)
sys.exit(0)
'''

STUB_CHECK = '#!/bin/bash\n[ -n "${FAKE_REMINDER:-}" ] && { echo "STUB reminder: rotate soon"; exit 1; }\nexit 0\n'


def check(name, good, detail=""):
    print(f"\033[32m[ PASS ]\033[0m {name}" if good else f"\033[31m[ FAIL ]\033[0m {name}\n{detail}", flush=True)
    if not good:
        FAILED.append(name)


def make_pod(ws, source):
    """A throwaway workspace ws/ with mycache at its real depth; source = 'new' (this tree) or a git ref."""
    dest = ws / "projectspace/platform/mycache"
    (ws / "mountspace").mkdir(parents=True)
    if source == "new":
        shutil.copytree(POD, dest, ignore=shutil.ignore_patterns("credentials", ".git", "__pycache__", "memory"))
    else:
        dest.mkdir(parents=True)
        arch = subprocess.run(["git", "-C", str(POD), "archive", source], stdout=subprocess.PIPE)
        if arch.returncode:
            return None
        subprocess.run(["tar", "-x", "-C", str(dest)], input=arch.stdout, check=True)
    ic = dest / "cache-agent/issued_credentials"
    for f in ic.glob("*_check.sh"):                       # the reminder → a stub (never the real kms)
        if f.name != "credentials_check.sh":
            f.unlink()
    (ic / "stub_rotation_check.sh").write_text(STUB_CHECK)
    return dest


def run(pod, door, args=(), env=None, stdin=None, cwd=None, session=False):
    """bash <door> in the pod with the fake docker → (lines, exit code, docker calls)."""
    log, state = pod / "fake_docker.log", pod / "fake_state"
    log.write_text("")
    e = {**os.environ, "PATH": f"{BIN}:{os.environ['PATH']}", "FAKE_LOG": str(log), "FAKE_STATE": str(state),
         "SVC_RUN": "1", **(env or {})}
    e.pop("LOG_FILE", None)
    r = subprocess.run(["bash", str(pod / f"{door}.sh"), *args], cwd=cwd or pod, env=e, input=stdin,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       stdin=None if stdin is not None else subprocess.DEVNULL, start_new_session=session)
    out = r.stdout.replace(str(pod), "<POD>")
    return out, r.returncode, log.read_text()


def same(name, door, args=(), env=None, stdin=None, state=None, expect=None, session=False, prepare=None):
    """Run the case on the old and the new pod — the same lines, exit code and docker calls (+ expect on the new)."""
    results = {}
    for side, pod in PODS.items():
        (pod / "fake_state").write_text("\n".join(state or []) + "\n")
        if prepare:
            prepare(pod)
        results[side] = run(pod, door, args, env, stdin, session=session)
    new = results["new"]
    good = expect(*new) if expect else True
    detail = f"  new: rc={new[1]}\n{new[0]}{new[2]}"
    if "old" in results:
        old = results["old"]
        good = good and old == new
        detail += f"\n  old: rc={old[1]}\n{old[0]}{old[2]}"
    check(name, good, detail)
    return new


# ── L0 the real doors ──────────────────────────────────────────────────────────────────────────────────────────
bad = []
for d in DOORS:
    if starter and starter.complex_logic(POD / f"{d}.sh"):
        bad.append(f"{d}.sh: {starter.complex_logic(POD / f'{d}.sh')}")
    h = subprocess.run(["bash", str(POD / f"{d}.sh"), "--help"], stdout=subprocess.PIPE, text=True,
                       stderr=subprocess.STDOUT).stdout
    if f"{d}.sh" not in h.splitlines()[0] if h else True:
        bad.append(f"{d}.sh --help: {h[:80]!r}")
for f in HERE.glob("*.py"):
    try:
        compile(f.read_text(), str(f), "exec")
    except SyntaxError as e:
        bad.append(f"{f.name}: {e}")
check("L0 the doors: invoking lines only · --help shows the guide · every .py compiles", not bad, "\n".join(bad))

TMP = pathlib.Path(tempfile.mkdtemp(prefix="mycache-lifecycle-"))
try:
    BIN = TMP / "bin"
    BIN.mkdir()
    (BIN / "docker").write_text(FAKE_DOCKER)
    (BIN / "docker").chmod(0o755)
    PODS = {"new": make_pod(TMP / "new/ws", "new")}
    old = make_pod(TMP / "old/ws", OLD_REF)
    if old:
        PODS["old"] = old
    else:
        print(f"\033[33m[ WARN ]\033[0m OLD_REF {OLD_REF} not in git — only the new side runs (no old = new)")
    for pod in PODS.values():                             # signed up: a fake login file (no value anywhere real)
        cred = pod / "cache-agent/connect_external/kms/credentials/mycache-cache-agent"
        cred.mkdir(parents=True, exist_ok=True)
        (cred / "secret_id").write_text("fake\n")

    R, U = ["mycache-redis"], ["mycache-redis", "mycache-redis-ui"]
    same("L1 state: running", "state", state=R, expect=lambda o, rc, d: o == "running\n" and rc == 0)
    same("L1 state: stopped (a Restarting one too)", "state", env={"FAKE_RESTARTING": "mycache-redis"},
         expect=lambda o, rc, d: o == "stopped\n")
    same("L2 status: compose ps", "status", state=R, expect=lambda o, rc, d: "fake compose ps" in o and rc == 0)
    same("L2 status: compose ps fails → its exit code", "status", env={"FAKE_COMPOSE_RC": "4"},
         expect=lambda o, rc, d: rc == 4)
    same("L3 start: Redis + UI, the full output", "start",
         expect=lambda o, rc, d: rc == 0 and "==> Redis is up" in o and "kv/data/mycache/redis" in o
         and d.strip() == "compose up -d")
    same("L3 start --no-ui: Redis only + the note", "start", ["--no-ui"],
         expect=lambda o, rc, d: rc == 0 and "Redis UI not started (--no-ui)" in o and "compose up -d redis" in d)
    same("L3 start: compose up fails → its exit code, no 'Redis is up'", "start", env={"FAKE_COMPOSE_RC": "3"},
         expect=lambda o, rc, d: rc == 3 and "Redis is up" not in o)

    def unsigned(pod, filled):
        shutil.rmtree(pod / "cache-agent/connect_external/kms/credentials", ignore_errors=True)
        mp = pod.parents[2] / "mountspace/usb/myworkspace/projectspace/kms/master_password"
        mp.mkdir(parents=True, exist_ok=True)
        (mp / "master_password").write_text("not-a-real-password\n" if filled else "")

    same("L4 start: not signed up, master_password filled → INFO, starts", "start",
         prepare=lambda p: unsigned(p, True),
         expect=lambda o, rc, d: rc == 0 and "signs itself up as it starts" in o)
    same("L4 start: not signed up, master_password empty, by a script → ERROR exit 1, nothing started", "start",
         prepare=lambda p: unsigned(p, False),
         expect=lambda o, rc, d: rc == 1 and "is not signed up with kms yet" in o and "compose" not in d)
    for pod in PODS.values():
        (pod / "cache-agent/connect_external/kms/credentials/mycache-cache-agent").mkdir(parents=True, exist_ok=True)
        (pod / "cache-agent/connect_external/kms/credentials/mycache-cache-agent/secret_id").write_text("fake\n")

    same("L5 start: .env missing → ERROR exit 1", "start", prepare=lambda p: (p / ".env").rename(p / ".env.away"),
         expect=lambda o, rc, d: rc == 1 and ".env not found." in o)
    for pod in PODS.values():
        (pod / ".env.away").rename(pod / ".env")

    same("L6 stop: compose down + 'Data is preserved'", "stop", state=U,
         expect=lambda o, rc, d: rc == 0 and "Data is preserved" in o and d.strip() == "compose down")
    same("L6 stop: compose down fails → its exit code", "stop", env={"FAKE_COMPOSE_RC": "2"},
         expect=lambda o, rc, d: rc == 2 and "Data is preserved" not in o)
    same("L7 ensure_running: already running → OK, nothing started", "ensure_running", state=U,
         expect=lambda o, rc, d: rc == 0 and "Redis already running" in o and "compose" not in d)
    same("L7 ensure_running --no-ui: Redis alone is enough", "ensure_running", ["--no-ui"], state=R,
         expect=lambda o, rc, d: rc == 0 and "Redis already running" in o)
    same("L7 ensure_running: stopped, no network → network made · start.sh · OK", "ensure_running",
         env={"FAKE_NET_MISSING": "1"},
         expect=lambda o, rc, d: rc == 0 and "Redis running" in o and "network create" in d and "compose up" in d)
    same("L7 ensure_running: still not running after start.sh → ERROR exit 1", "ensure_running",
         env={"FAKE_UP_FAILS": "1"}, expect=lambda o, rc, d: rc == 1 and "not running after start.sh" in o)
    same("L7 ensure_running: start.sh fails → ERROR 'start.sh failed'", "ensure_running",
         env={"FAKE_COMPOSE_RC": "5"}, expect=lambda o, rc, d: rc == 1 and "start.sh failed" in o)
    same("L8 ensure_stopped: nothing runs → already stopped", "ensure_stopped",
         expect=lambda o, rc, d: rc == 0 and "already stopped" in o and "compose" not in d)
    same("L8 ensure_stopped: the UI alone runs → stop.sh", "ensure_stopped", state=["mycache-redis-ui"],
         expect=lambda o, rc, d: rc == 0 and "compose down" in d)
    same("L9 destroy: 'no' → Aborted, nothing removed", "destroy", stdin="no\n", state=U,
         expect=lambda o, rc, d: rc == 0 and "Aborted." in o and "compose" not in d)
    same("L9 destroy: 'yes' → down -v --remove-orphans", "destroy", stdin="yes\n", state=U,
         expect=lambda o, rc, d: rc == 0 and "compose down -v --remove-orphans" in d and "All Redis data deleted" in o)
    same("L9 destroy: no input at all → exit 1, nothing removed", "destroy", stdin="",
         expect=lambda o, rc, d: rc == 1 and "compose" not in d)
    same("L10 logs: compose logs -f --tail=100", "logs",
         expect=lambda o, rc, d: rc == 0 and d.strip() == "compose logs -f --tail=100")
    same("L11 login: unknown container → refused", "mycache_container_login", ["nope"],
         expect=lambda o, rc, d: rc == 1 and "'nope' is not one of mycache's containers" in o)
    same("L11 login: docker down → refused", "mycache_container_login", env={"FAKE_DOCKER_DOWN": "1"},
         expect=lambda o, rc, d: rc == 1 and "Docker is not running" in o)
    same("L11 login: not running → refused + how to start", "mycache_container_login",
         expect=lambda o, rc, d: rc == 1 and "is not running — start it: bash" in o)
    same("L11 login: no terminal → refused", "mycache_container_login", state=R, session=True,
         expect=lambda o, rc, d: rc == 1 and "this needs a terminal" in o)
    same("L12 the reminder shows in start and never stops it", "start", env={"FAKE_REMINDER": "1"},
         expect=lambda o, rc, d: rc == 0 and "STUB reminder" in o and "Redis is up" in o)
    same("L12 the reminder shows in stop and never stops it", "stop", env={"FAKE_REMINDER": "1"},
         expect=lambda o, rc, d: rc == 0 and "STUB reminder" in o and "Redis stopped" in o)

    # L13 the guard: the pod one level too high (old folder) → refuses; old and new alike (the new says it first)
    good, detail = True, ""
    for side, pod in PODS.items():
        high = pod.parents[2] / "projectspace/mycache"
        shutil.copytree(pod, high)
        out, rc, d = run(high, "start")
        good = good and rc == 1 and "this pod is not at its folder" in out and "compose" not in d
        detail += f"  {side}: rc={rc}\n{out}"
    check("L13 start's pod guard: one level too high → refuses, nothing started (old and new)", good, detail)
finally:
    shutil.rmtree(TMP, ignore_errors=True)

if FAILED:
    print(f"\033[31m{len(FAILED)} FAILED\033[0m: " + " · ".join(f.split(":")[0] for f in FAILED))
    sys.exit(1)
print(f"\033[32mALL PASS\033[0m — old = new{'' if 'old' in PODS else ' (new only)'}")
