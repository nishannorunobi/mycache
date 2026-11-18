#!/usr/bin/env python3
"""test_credentials.py — mycache's issued credentials (this folder) on a THROWAWAY kms only. The door: test_credentials.sh.

    C0  static (the real files): every door --help + bash -n · the .py compile · lifecycle/start.py + stop.py call
        credentials_check.sh and never stop for it · the runner finds *_check.sh by itself
    C1  fine (90-day rule, written today): by hand OK + "rotate by", exit 0 · --quiet + the runner: nothing, exit 0
    C2  within the window (a 3-day rule): exit 1, WARN "rotate in 3 days" + "do: …redis_password_rotate.sh" · runner too
    C3  overdue ("today" = 100 days on): exit 1 (never 2), WARN "overdue by 10 days … nothing stops" + "do:"
    C4  kms down: exit 3, WARN — never the real kms (KMS_URL set = the only one tried)
    C5  not signed up: exit 3, WARN + the sign-up line
    C6  credentials.conf missing / garbage → 7 and 90 + a WARN each
    C7  SECRET_MGT=local → OK "no kms date", exit 0
    L1  the password and the login never on screen
    OLD every case C1–C7 also on the old bash (git OLD_REF) in its own throwaway workspace → the same lines + exit codes

Nothing real: a throwaway kms (openbao, :8122), its own shares + owner password, every KMS_* folder in a temp dir.
"""
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in pathlib.Path(__file__).resolve().parents
                if (p / "mountspace").is_dir()][:1]
try:
    import starter
    starter.start()
except ImportError:
    starter = None

HERE = pathlib.Path(__file__).resolve().parent
AGENT = HERE.parent
PROJ = AGENT.parent
WS = next(p for p in PROJ.parents if (p / "mountspace").is_dir())
KMSP = WS / "projectspace/platform/kms"
DS = KMSP / "dockerspace"
OLD_REF = os.environ.get("OLD_REF", "709477f")
T, PORT, ROLE = "kms-credentials-test", 8122, "mycache-cache-agent"
U = f"http://127.0.0.1:{PORT}"
FAILED = []


def ok(text):
    print(f"\033[32m[  OK  ]\033[0m {text}", flush=True)


def bad(text):
    print(f"\033[31m[ERROR]\033[0m  {text}", flush=True)
    FAILED.append(text.split(":")[0])


def http(method, path, body=None, token=None):
    req = urllib.request.Request(f"{U}/v1/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    if token:
        req.add_header("X-Vault-Token", token)
    try:
        with urllib.request.urlopen(req, timeout=60 if path != "sys/health" else 3) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {}
    except (urllib.error.URLError, OSError):
        return 0, {}


def wait_health(code):
    for _ in range(30):
        if http("GET", "sys/health")[0] == code:
            return
        time.sleep(1)


# ── C0 static (the real files) ────────────────────────────────────────────────────────────────────────────────
s = []
for f in sorted(HERE.glob("*.sh")):
    if subprocess.run(["bash", "-n", str(f)]).returncode:
        s.append(f"{f.name}:syntax")
    first = subprocess.run(["bash", str(f), "--help"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           text=True).stdout.strip()
    if not first:
        s.append(f"{f.name}:--help")
    if starter and starter.complex_logic(f):
        s.append(f"{f.name}:not only invoking lines {starter.complex_logic(f)}")
for f in HERE.glob("*.py"):
    try:
        compile(f.read_text(), str(f), "exec")
    except SyntaxError:
        s.append(f"{f.name}:py-compile")
for f in ("start.py", "stop.py"):
    if 'pod.door("cache-agent/issued_credentials/credentials_check.sh")\n' not in (PROJ / "lifecycle" / f).read_text():
        s.append(f"lifecycle/{f}:call")
if 'HERE.glob("*_check.sh")' not in (HERE / "credentials_check.py").read_text():
    s.append("runner:discovery")
if not s:
    ok("C0 static: --help · syntax · invoking lines only · lifecycle start/stop call credentials_check.sh "
       "(its exit ignored) · the runner finds *_check.sh")
else:
    bad("C0 static: " + " ".join(s))

# ── throwaway workspaces: the code under test (new = this folder · old = git OLD_REF), nothing real ───────────
TMP = pathlib.Path(tempfile.mkdtemp(prefix="mycache-credentials-"))
DATA, AUDIT = TMP / "data", TMP / "audit"
DATA.mkdir()
AUDIT.mkdir()


def make_ws(name, files):
    """files: {name: bytes} for issued_credentials/ + kms_transfer.py → the C folder of a throwaway workspace."""
    a = TMP / name / "ws/projectspace/platform/mycache/cache-agent"
    (TMP / name / "ws/mountspace").mkdir(parents=True)
    (a / "issued_credentials").mkdir(parents=True)
    (a / "connect_external/kms").mkdir(parents=True)
    for fname, data in files.items():
        (a / ("connect_external/kms" if fname == "kms_transfer.py" else "issued_credentials") / fname).write_bytes(data)
    return a


def git_files(ref):
    names = subprocess.run(["git", "-C", str(PROJ), "ls-tree", "--name-only", ref, "cache-agent/issued_credentials/"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    if names.returncode:
        return None
    files = {}
    for path in names.stdout.split() + ["cache-agent/connect_external/kms/kms_transfer.py"]:
        if re.search(r"\.(sh|py)$|credentials\.conf$", path) and "test_" not in path:
            files[os.path.basename(path)] = subprocess.run(["git", "-C", str(PROJ), "show", f"{ref}:{path}"],
                                                           stdout=subprocess.PIPE).stdout
    return files


new_files = {f.name: f.read_bytes() for f in HERE.iterdir()
             if (f.suffix in (".sh", ".py") or f.name == "credentials.conf") and not f.name.startswith("test_")}
new_files["kms_transfer.py"] = (AGENT / "connect_external/kms/kms_transfer.py").read_bytes()
SIDES = {"new": make_ws("new", new_files)}
old_files = git_files(OLD_REF)
if old_files:
    SIDES["old"] = make_ws("old", old_files)
else:
    print(f"\033[33m[ WARN ]\033[0m OLD_REF {OLD_REF} not in git — only the new side runs (no old = new)")


def conf(mode="kms"):
    for a in SIDES.values():
        (a / "agent.conf").write_text(f"KMS_URL={U}\nSECRET_MGT={mode}\nREDIS_PASSWORD=${{KMS_URL}}/v1/kv/data/mycache/redis\n")


def rules(warn, rotate):
    for a in SIDES.values():
        (a / "issued_credentials/credentials.conf").write_text(f"WARN_BEFORE_DAYS={warn}\nROTATE_AFTER_DAYS={rotate}\n")


conf()
rules(7, 90)
APPROLE = TMP / "approle"
CRED = APPROLE / ROLE
CRED.mkdir(parents=True)
os.chmod(APPROLE, 0o700)
os.chmod(CRED, 0o700)
os.environ.update({"KMS_URL": U, "KMS_APPROLE_DIR": str(APPROLE), "KMS_STATE_DIR": str(TMP / "state"),
                   "KMS_SECRETS_DIR": str(TMP / "secrets/kms"), "KMS_ALLOWED_CIDRS": "172.16.0.0/12,127.0.0.1/32",
                   "KMS_STATIC_KEY_DIR": str(TMP / "usb"), "KMS_USB_BACKUP_DIR": str(TMP / "usbbk"),
                   "KMS_MASTER_PASSWORD_FILE": str(TMP / "master_password")})
os.environ.pop("LOG_FILE", None)

ALL = ""


def run(side, script, *args, env=None):
    """bash <script> on one side → (lines with the workspace path as <WS>, exit code)."""
    global ALL
    r = subprocess.run(["bash", str(SIDES[side] / "issued_credentials" / script), *args],
                       env={**os.environ, **(env or {})}, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    ALL += r.stdout
    return r.stdout.replace(str(SIDES[side].parents[3]), "<WS>"), r.returncode


def case(name, script, *args, env=None, expect):
    """The case on every side: expect(out, rc) on the new · the old prints the same lines, the same exit code."""
    out, rc = run("new", script, *args, env=env)
    good, detail = expect(out, rc), f"new rc={rc}: {out}"
    if "old" in SIDES:
        o_out, o_rc = run("old", script, *args, env=env)
        good = good and (o_out, o_rc) == (out, rc)
        detail += f"\n  old rc={o_rc}: {o_out}"
    ok(name) if good else bad(f"{name}: {detail}")


try:
    # ── the throwaway kms ────────────────────────────────────────────────────────────────────────────────────
    image = re.search(r"^OPENBAO_IMAGE=(.*)$", (DS / ".env").read_text(), re.M).group(1)   # only the image
    subprocess.run(["docker", "rm", "-f", T], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    r = subprocess.run(["docker", "run", "-d", "--name", T, "-p", f"127.0.0.1:{PORT}:8200",
                        "--user", f"{os.getuid()}:{os.getgid()}", "-e", "SKIP_CHOWN=true",
                        "-v", f"{DS}/config:/openbao/config:ro", "-v", f"{DATA}:/openbao/data",
                        "-v", f"{AUDIT}:/openbao/audit", image, "server"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if r.returncode:
        bad(f"throwaway kms did not start: {r.stderr.strip()}")
        raise SystemExit
    wait_health(501)
    _, init = http("PUT", "sys/init", {"secret_shares": 3, "secret_threshold": 2})
    s1, s2 = init["keys_base64"][0], init["keys_base64"][1]
    for k in (s1, s2):
        http("PUT", "sys/unseal", {"key": k})
    wait_health(200)
    pw = "pw-" + os.urandom(12).hex()
    b = subprocess.run(["bash", str(KMSP / "bootstrap.sh")], input=f"{s1}\n{s2}\n{pw}\n{pw}\n", text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if b.returncode:                                      # only its error lines — its output names a share
        bad("bootstrap failed: " + " | ".join(l for l in b.stdout.splitlines() if re.search(r"ERROR|FAIL|✗", l)))
        raise SystemExit
    _, login = http("POST", "auth/userpass/login/nishan", {"password": pw})
    ot = (login.get("auth") or {}).get("client_token")
    if not ot:
        bad("owner login on the throwaway kms failed")
        raise SystemExit
    rp = "redis-" + os.urandom(12).hex()
    http("POST", "kv/data/mycache/redis", {"data": {"REDIS_PASSWORD": rp}}, ot)
    http("PUT", f"sys/policies/acl/{ROLE}", {"policy": 'path "kv/data/mycache/redis" { capabilities = ["read"] }\n'
                                                       'path "kv/data/mycache/redis/*" { capabilities = ["read"] }\n'}, ot)
    http("POST", f"auth/approle/role/{ROLE}", {"token_policies": ROLE, "token_ttl": "1h"}, ot)
    (CRED / "role_id").write_text(http("GET", f"auth/approle/role/{ROLE}/role-id", token=ot)[1]["data"]["role_id"] + "\n")
    secret_id = http("POST", f"auth/approle/role/{ROLE}/secret-id", {}, ot)[1]["data"]["secret_id"]
    (CRED / "secret_id").write_text(secret_id + "\n")
    os.chmod(CRED / "role_id", 0o600)
    os.chmod(CRED / "secret_id", 0o600)

    today = datetime.date.today()
    due90 = (today + datetime.timedelta(days=90)).isoformat()
    CHK, RUNNER = "redis_password_rotation_check.sh", "credentials_check.sh"

    case(f"C1 fine: by hand → OK, changed {today}, rotate by {due90}", CHK,
         expect=lambda o, rc: rc == 0 and f"Redis password changed {today} — rotate by {due90}, 90 days left (reminds at 7)" in o)
    case("C1 --quiet: nothing printed, exit 0", CHK, "--quiet", expect=lambda o, rc: rc == 0 and o == "")
    case("C1 credentials_check.sh (start/stop): silent, exit 0", RUNNER, expect=lambda o, rc: rc == 0 and o == "")

    rules(7, 3)
    case("C2 within 7 days: exit 1, WARN rotate in 3 days + do: …redis_password_rotate.sh", CHK, "--quiet",
         expect=lambda o, rc: rc == 1 and re.search(r"Redis password: rotate in 3 days \(due .* · 3-day rule\)", o)
         and re.search(r"do: bash .*issued_credentials/redis_password_rotate.sh", o))
    case("C2 the runner shows it, exit 1", RUNNER, expect=lambda o, rc: rc == 1 and "rotate in 3 days" in o)

    rules(7, 90)
    later = (today + datetime.timedelta(days=100)).isoformat()
    case("C3 overdue: exit 1 (a reminder, never 2), WARN overdue by 10 days + do:", CHK, "--quiet",
         env={"CREDENTIALS_CHECK_TODAY": later},
         expect=lambda o, rc: rc == 1 and re.search(r"rotation overdue by 10 days \(was due .* · 90-day rule\) — nothing stops", o)
         and "do: bash" in o)
    case("C4 kms down: exit 3, WARN — never the real kms", CHK, "--quiet", env={"KMS_URL": "http://127.0.0.1:1"},
         expect=lambda o, rc: rc == 3 and "kms does not answer" in o)
    case("C5 not signed up: exit 3, WARN + the sign-up line", CHK, "--quiet", env={"KMS_APPROLE_DIR": str(TMP / "none")},
         expect=lambda o, rc: rc == 3 and re.search(r"no kms login yet .*signup_with_kms.sh", o))

    for a in SIDES.values():
        (a / "issued_credentials/credentials.conf").unlink()
    case("C6 credentials.conf missing → 7 and 90 + a WARN each", CHK,
         expect=lambda o, rc: rc == 0 and "WARN_BEFORE_DAYS is missing — using 7" in o
         and "ROTATE_AFTER_DAYS is missing — using 90" in o and f"rotate by {due90}" in o)
    rules("x", "y")
    case("C6 garbage → 7 and 90 + a WARN each", CHK,
         expect=lambda o, rc: "WARN_BEFORE_DAYS is 'x' — using 7" in o and "ROTATE_AFTER_DAYS is 'y' — using 90" in o)
    rules(7, 90)

    conf("local")
    case("C7 SECRET_MGT=local → OK, no kms date, exit 0", CHK,
         expect=lambda o, rc: rc == 0 and "SECRET_MGT is not kms — no kms date" in o)
    conf()

    if rp not in ALL and secret_id not in ALL:
        ok("L1 the password and the login never on screen")
    else:
        bad("L1 a secret was printed")
except SystemExit:
    pass
finally:
    subprocess.run(["docker", "rm", "-f", T], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(TMP, ignore_errors=True)

if FAILED:
    bad(f"FAILED — {len(FAILED)}: " + " · ".join(FAILED))
    sys.exit(1)
ok("ALL PASS" + (" — old = new" if "old" in SIDES else ""))
