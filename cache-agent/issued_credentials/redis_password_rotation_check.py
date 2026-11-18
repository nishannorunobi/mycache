#!/usr/bin/env python3
"""redis_password_rotation_check.py — the 90-day rotation reminder for ONE issued key: mycache's Redis password.

Called by redis_password_rotation_check.sh (you, by hand) and, through credentials_check.sh, by start.sh / stop.sh.
mycache ISSUES the Redis password (it is the server). The password never expires — the rotation rule (KMS-79,
ROTATE_AFTER_DAYS in credentials.conf, default 90) says it gets a new value that many days after its last change.
The date of the last change is kms's own: the entry's current version `created_time`, read with mycache's OWN kms
login (it may read its entry — no new permission, no password). Prints:

    --quiet (start / stop)   nothing while more than WARN_BEFORE_DAYS are left
    by hand                  [  OK  ] mycache · Redis password changed 2026-10-05 — rotate by 2027-01-03, 56 days left (reminds at 7)
    within the window        [ WARN ] … rotate in 5 days (due 2027-01-03 · 90-day rule) + "do: bash …/redis_password_rotate.sh"
    overdue                  [ WARN ] … rotation overdue by 3 days (was due …) — nothing stops + "do: …"

Exit: 0 fine · 1 due within WARN_BEFORE_DAYS or overdue (a reminder — never 2: nothing expires) ·
3 cannot tell (kms down, not signed up, the entry not readable).
Standard library only. The value is never printed — only the date of its last change.
"""
import json, os, re, sys, urllib.error, urllib.request
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))                    # cache-agent/issued_credentials
AGENT = os.path.dirname(HERE)                                         # cache-agent
KMS_DIR = os.path.join(AGENT, "connect_external", "kms")
sys.path.insert(0, KMS_DIR)
from kms_transfer import LOCAL_PC, healthy, say                      # mycache's own kms client (same rules)

ROLE = "mycache-cache-agent"                                          # = signup_with_kms.sh's login of the cache-agent
KEY = "REDIS_PASSWORD"                                                # its line in agent.conf: the kms address
WHO = "mycache"
WHAT = "Redis password"
DEFAULT_WARN_DAYS = 7
DEFAULT_ROTATE_DAYS = 90


def ws_root():
    d = HERE
    while d != "/" and not os.path.isdir(os.path.join(d, "mountspace")):
        d = os.path.dirname(d)
    return d


def rel(path):                                                        # a path the owner can paste from ~/myworkspace
    root = ws_root()
    return os.path.relpath(path, root) if root != "/" else path


ROTATE = rel(os.path.join(HERE, "redis_password_rotate.sh"))
SIGNUP = rel(os.path.join(KMS_DIR, "signup_with_kms.sh"))


def conf_value(path, key):
    try:
        for ln in open(path, encoding="utf-8"):
            m = re.match(rf"^\s*{key}\s*=\s*(.*?)\s*$", ln)
            if m:
                return m.group(1).strip("\"'")
    except OSError:
        pass
    return None


def days_setting(key, default):
    v = conf_value(os.path.join(HERE, "credentials.conf"), key)
    if v is not None and v.isdigit():
        return int(v)
    say("WARN", f"credentials.conf {key} is {'missing' if v is None else repr(v)} — using {default}")
    return default


def kms_url():
    """env KMS_URL (set = the ONLY one tried: the caller named kms) · else agent.conf's KMS_URL → kms on this PC —
    the first that answers, else None"""
    if os.environ.get("KMS_URL"):
        u = os.environ["KMS_URL"].rstrip("/")
        return u if healthy(u) else None
    for u in (conf_value(os.path.join(AGENT, "agent.conf"), "KMS_URL") or "", LOCAL_PC):
        u = u.rstrip("/")
        if u and "${" not in u and healthy(u):
            return u
    return None


def entry_path():
    """agent.conf REDIS_PASSWORD=${KMS_URL}/v1/kv/data/<entry>[#KEY] → 'kv/data/<entry>' (None: not a kms address)"""
    m = re.search(r"/v1/(kv/data/[^#\s]+)", conf_value(os.path.join(AGENT, "agent.conf"), KEY) or "")
    return m.group(1) if m else None


def call(url, method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f"{url}/v1/{path}", data=data, method=method)
    if token:
        req.add_header("X-Vault-Token", token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}
    except Exception as e:                                            # unreachable mid-way
        return 0, {"errors": [str(e)]}


def parse_time(s):
    """kms's RFC 3339 time (nanoseconds, Z or ±hh:mm) → aware datetime · anything else → None"""
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:\d\d)?$", s or "")
    if not m or m.group(1).startswith("0001-"):
        return None
    t = datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
    z = m.group(2) or "Z"
    off = timedelta(0) if z == "Z" else (1 if z[0] == "+" else -1) * timedelta(hours=int(z[1:3]), minutes=int(z[4:6]))
    return t.replace(tzinfo=timezone(off))


def days_text(n):
    return f"{n} day{'s' if n != 1 else ''}"


def main(argv):
    quiet = "--quiet" in argv
    if (conf_value(os.path.join(AGENT, "agent.conf"), "SECRET_MGT") or "local").lower() != "kms":
        if not quiet:
            say("OK", f"{WHO} · SECRET_MGT is not kms — no kms date for the {WHAT}, no reminder")
        return 0
    path = entry_path()
    if not path:
        say("WARN", f"{WHO} · {WHAT}: agent.conf {KEY} is not a kms address — its age could not be checked")
        return 3
    cred = os.path.join(os.environ.get("KMS_APPROLE_DIR") or os.path.join(KMS_DIR, "credentials"), ROLE)
    rid_f, sid_f = os.path.join(cred, "role_id"), os.path.join(cred, "secret_id")
    if not (os.path.isfile(rid_f) and os.path.isfile(sid_f)):
        say("WARN", f"{WHO} · no kms login yet — it signs itself up at its first start · or now: bash {SIGNUP}")
        return 3
    window = days_setting("WARN_BEFORE_DAYS", DEFAULT_WARN_DAYS)
    rule = days_setting("ROTATE_AFTER_DAYS", DEFAULT_ROTATE_DAYS)
    url = kms_url()
    if not url:
        say("WARN", f"{WHO} · {WHAT}: kms does not answer (not running / sealed) — its age could not be checked")
        return 3
    rid, sid = open(rid_f).read().strip(), open(sid_f).read().strip()
    code, res = call(url, "POST", "auth/approle/login", {"role_id": rid, "secret_id": sid})
    tok = (res.get("auth") or {}).get("client_token")
    if not tok:
        err = "; ".join(res.get("errors") or []) or f"HTTP {code}"
        say("WARN", f"{WHO} · {WHAT}: kms refused mycache's login ({err}) — its age could not be checked")
        return 3
    try:
        code, res = call(url, "GET", path, token=tok)
    finally:
        call(url, "POST", "auth/token/revoke-self", {}, tok)          # the 1-hour pass is not kept
    meta = ((res.get("data") or {}).get("metadata") or {}) if code == 200 else {}
    changed = parse_time(meta.get("created_time", ""))
    res = None                                                        # the value is never kept nor printed
    if changed is None:
        say("WARN", f"{WHO} · {WHAT}: {path[len('kv/data/'):]} could not be read (HTTP {code}) — its age could not be checked")
        return 3
    changed_day = changed.astimezone().date()                         # days count on THIS PC's calendar
    due_day = changed_day + timedelta(days=rule)
    today = os.environ.get("CREDENTIALS_CHECK_TODAY")                # tests only: "today" as YYYY-MM-DD
    today_day = datetime.strptime(today, "%Y-%m-%d").date() if today else datetime.now().astimezone().date()
    left = (due_day - today_day).days
    when_changed, when_due = changed_day.isoformat(), due_day.isoformat()
    if left < 0:
        say("WARN", f"{WHO} · {WHAT}: rotation overdue by {days_text(-left)} (was due {when_due} · {rule}-day rule) — nothing stops")
        print(f"         do: bash {ROTATE}", flush=True)
        return 1
    if left <= window:
        say("WARN", f"{WHO} · {WHAT}: rotate in {days_text(left)} (due {when_due} · {rule}-day rule)")
        print(f"         do: bash {ROTATE}", flush=True)
        return 1
    if not quiet:
        say("OK", f"{WHO} · {WHAT} changed {when_changed} — rotate by {when_due}, {days_text(left)} left (reminds at {window})")
    return 0


if __name__ == "__main__":
    # by hand: --help + the mirror log, as usual · --quiet (credentials_check.py): no log here — the runner logs it
    import pathlib
    sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in pathlib.Path(HERE).parents
                    if (p / "mountspace").is_dir()][:1]
    try:
        import starter
        if "--quiet" not in sys.argv[1:]:
            starter.start()
    except ImportError:
        pass                                                          # a temp copy: no --help, no mirror log
    sys.exit(main(sys.argv[1:]))
