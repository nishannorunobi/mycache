#!/usr/bin/env python3
"""test_agent_doors.py — the cache-agent's host doors (host_start · host_status · host_stop) and its in-container
doors (health · start) against a FAKE agent and a FAKE docker. The door: test_agent_doors.sh (its --help).

    H0  every door: invoking lines only · --help shows its guide · every .py compiles
    H1  old = new, read-only on THIS PC: host_status · --state · host_start (agent answers → "already running") ·
        host_stop · in-container health / start run on the host (the old bash from git OLD_REF)
    H2  host_status: fake agent up → running · down → stopped (human line + --state)
    H3  host_start: answers → "already running", nothing started
    H4  host_start: container down → ../../start.sh --no-ui → answers → OK
    H5  host_start: never answers → ERROR + only the container's [agent] lines, exit 1
    H6  host_start's log: its folder not writable (the container's, root) → …/mycache/cache-agent_host_start_sh.log
    H7  in-container health: ok / down · start: OK exit 0 / WARN exit 1 · LOG_MIRROR_ROOT → the same log file as before
Nothing real is changed: a throwaway workspace, a fake agent on a free port, a fake docker first on PATH.
"""
import http.server
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading

sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in pathlib.Path(__file__).resolve().parents
                if (p / "mountspace").is_dir()][:1]
try:
    import starter
    starter.start()
except ImportError:
    starter = None

HERE = pathlib.Path(__file__).resolve().parent
AGENT = HERE.parent
POD = AGENT.parent
WS = next(str(p) for p in POD.parents if (p / "mountspace").is_dir())
OLD_REF = os.environ.get("OLD_REF", "709477f")
DOORS = ["host_start", "host_status", "host_stop", "health", "start"]
FAILED = []
STAMP = re.compile(r"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] ", re.M)

FAKE_DOCKER = r'''#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(" ".join(a) + "\n")
if a[:1] == ["inspect"]:
    print("true" if os.environ.get("FAKE_RUNNING") else "false")
if a[:1] == ["logs"]:
    print("redis ready\n[agent] kms is SEALED — waiting")
'''
STUB_START = '#!/bin/bash\necho "STUB start.sh $*"\ntouch "$FAKE_UP"\n'


def check(name, good, detail=""):
    print(f"\033[32m[ PASS ]\033[0m {name}" if good else f"\033[31m[ FAIL ]\033[0m {name}\n{detail}", flush=True)
    if not good:
        FAILED.append(name)


def clean(text):
    return "\n".join(l for l in STAMP.sub("", text).splitlines() if not l.startswith("[logging]"))


def run(door, *args, env=None, split=False):
    e = {**os.environ, **(env or {})}
    e.pop("LOG_FILE", None)
    r = subprocess.run(["bash", str(door), *args], env=e, text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE if split else subprocess.STDOUT)
    return r.stdout, r.returncode, (r.stderr if split else "")


# ── H0 the real doors ──────────────────────────────────────────────────────────────────────────────────────────
bad = []
for d in DOORS:
    door = AGENT / f"{d}.sh"
    if starter and starter.complex_logic(door):
        bad.append(f"{d}.sh: {starter.complex_logic(door)}")
    first = (clean(run(door, "--help")[0]).splitlines() or [""])[0]
    if f"{d}.sh" not in first:
        bad.append(f"{d}.sh --help: {first!r}")
for f in list(HERE.glob("*.py")) + list((AGENT / "host_lifecycle").glob("*.py")) + list((AGENT / "in_container").glob("*.py")):
    try:
        compile(f.read_text(), str(f), "exec")
    except SyntaxError as e:
        bad.append(f"{f.name}: {e}")
check("H0 the doors: invoking lines only · --help shows the guide · every .py compiles", not bad, "\n".join(bad))

TMP = pathlib.Path(tempfile.mkdtemp(prefix="mycache-agent-"))
try:
    # ── H1 old = new on this PC, read-only ────────────────────────────────────────────────────────────────────
    old = TMP / "old"
    old.mkdir()
    arch = subprocess.run(["git", "-C", str(POD), "archive", OLD_REF, "cache-agent"], stdout=subprocess.PIPE)
    if arch.returncode == 0 and subprocess.run(["bash", str(AGENT / "host_status.sh"), "--state"], text=True,
                                               stdout=subprocess.PIPE).stdout.strip() == "running":
        subprocess.run(["tar", "-x", "-C", str(old)], input=arch.stdout, check=True)
        oa, diffs = old / "cache-agent", []
        cases = [("host_status.sh",), ("host_status.sh", "--state"), ("host_start.sh",), ("host_stop.sh",),
                 ("health.sh",), ("start.sh",)]
        for case in cases:
            o, n = run(oa / case[0], *case[1:]), run(AGENT / case[0], *case[1:])
            o_txt, n_txt = clean(o[0]).replace(str(old), str(POD)), clean(n[0])
            if (o_txt, o[1]) != (n_txt, n[1]):
                diffs.append(f"{' '.join(case)}\n  old rc={o[1]}: {o_txt!r}\n  new rc={n[1]}: {n_txt!r}")
        check("H1 old = new on this PC (read-only): host_status · --state · host_start · host_stop · health · start",
              not diffs, "\n".join(diffs))
    else:
        print(f"\033[33m[ WARN ]\033[0m H1 skipped — OLD_REF {OLD_REF} not in git, or the cache-agent is not running here")

    # ── a fake agent: answers /health while the file UP exists ────────────────────────────────────────────────
    UP = TMP / "up"

    class Health(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200 if UP.exists() and self.path == "/health" else 503)
            self.end_headers()

        def log_message(self, *a):
            pass

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    PORT = sock.getsockname()[1]
    sock.close()
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Health)
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    BIN = TMP / "bin"
    BIN.mkdir()
    (BIN / "docker").write_text(FAKE_DOCKER)
    (BIN / "docker").chmod(0o755)
    TW = TMP / "ws"                                       # a throwaway workspace: the agent doors + a stub start.sh
    pod = TW / "projectspace/platform/mycache"
    shutil.copytree(AGENT, pod / "cache-agent",
                    ignore=shutil.ignore_patterns("credentials", "__pycache__", "memory", "fluent-bit"))
    (pod / "start.sh").write_text(STUB_START)
    (TW / "mountspace").mkdir()
    (TW / "ccc/scripts/lib").mkdir(parents=True)
    os.symlink(f"{WS}/ccc/scripts/lib/python_starter", TW / "ccc/scripts/lib/python_starter")
    DLOG = TMP / "docker.log"
    ENV = {"PATH": f"{BIN}:{os.environ['PATH']}", "CACHE_AGENT_URL": f"http://127.0.0.1:{PORT}",
           "FAKE_LOG": str(DLOG), "FAKE_UP": str(UP), "HOST_START_TRIES": "2"}
    ta = pod / "cache-agent"

    UP.touch()
    a, b = run(ta / "host_status.sh", env=ENV)[0], run(ta / "host_status.sh", "--state", env=ENV)[0]
    UP.unlink()
    c, d = run(ta / "host_status.sh", env=ENV)[0], run(ta / "host_status.sh", "--state", env=ENV)[0]
    check("H2 host_status: up → running · down → stopped (human + --state)",
          a.strip() == "Cache agent (:8892) inside mycache-redis: running" and b == "running\n"
          and c.strip().endswith(": stopped") and d == "stopped\n", f"{a}{b}{c}{d}")

    UP.touch()
    DLOG.write_text("")
    o, rc, _ = run(ta / "host_start.sh", env=ENV)
    check("H3 host_start: answers → already running, nothing started",
          rc == 0 and "[OK] Cache agent already running on :8892" in o and "STUB" not in o and DLOG.read_text() == "",
          o)
    UP.unlink()

    o, rc, _ = run(ta / "host_start.sh", env=ENV)
    check("H4 host_start: container down → start.sh --no-ui → answers → OK",
          rc == 0 and "[INFO] mycache-redis is not running" in o and "STUB start.sh --no-ui" in o
          and "[OK] Cache agent running on :8892" in o, o)
    UP.unlink()

    o, rc, _ = run(ta / "host_start.sh", env={**ENV, "FAKE_RUNNING": "1"})   # stderr: in the mirror log, as the bash
    check("H5 host_start: never answers → ERROR + only the container's [agent] lines, exit 1",
          rc == 1 and "the cache-agent does not answer" in o and "[agent] kms is SEALED" in o
          and "redis ready" not in o and "STUB" not in o, f"rc={rc}\n{o}")

    logs = TW / "mountspace/logs/ws/projectspace/platform/mycache"
    (logs / "cache-agent").mkdir(parents=True, exist_ok=True)
    (logs / "cache-agent").chmod(0o555)
    UP.touch()
    o, rc, _ = run(ta / "host_start.sh", env=ENV)
    (logs / "cache-agent").chmod(0o755)
    side = logs / "cache-agent_host_start_sh.log"
    check("H6 host_start's log: its folder not writable → cache-agent_host_start_sh.log next to it",
          rc == 0 and side.is_file() and "already running" in side.read_text(), o)

    # ── H7 in-container doors, run here with the fake agent ───────────────────────────────────────────────────
    lr = TMP / "mirror"
    conf = ta / "agent.conf"
    conf.write_text(re.sub(r"^PORT=.*$", f"PORT={PORT}", conf.read_text(), flags=re.M))
    e = {"PORT": str(PORT), "LOG_MIRROR_ROOT": str(lr), "CONTAINER_WORKDIR": str(TW / "projectspace/platform/mycache")}
    h_up, s_up = run(ta / "health.sh", env=e), run(ta / "start.sh", env=e)
    UP.unlink()
    h_dn, s_dn = run(ta / "health.sh", env=e), run(ta / "start.sh", env=e)
    plain = run(ta / "health.sh", env={"PORT": str(PORT)})[0]
    log = lr / "cache-agent/health_sh.log"
    check("H7 in-container: health ok/down (exit 0) · start OK exit 0 / WARN exit 1 · LOG_MIRROR_ROOT → "
          "cache-agent/health_sh.log stamped · not set → just the word",
          clean(h_up[0]) == "ok" and h_up[1] == 0 and clean(h_dn[0]) == "down" and h_dn[1] == 0
          and f"running on :{PORT}" in s_up[0] and s_up[1] == 0 and "not answering" in s_dn[0] and s_dn[1] == 1
          and log.is_file() and STAMP.search(log.read_text()) and plain == "down\n",
          f"{h_up}{h_dn}{s_up}{s_dn}{plain!r}")
    srv.shutdown()
finally:
    for p in TMP.rglob("*"):
        if p.is_dir() and not p.is_symlink():
            p.chmod(0o755)
    shutil.rmtree(TMP, ignore_errors=True)

if FAILED:
    print(f"\033[31m{len(FAILED)} FAILED\033[0m: " + " · ".join(f.split(":")[0] for f in FAILED))
    sys.exit(1)
print("\033[32mALL PASS\033[0m")
