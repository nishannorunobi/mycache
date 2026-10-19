#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────────────────────
# kms_transfer.py — the ROTATION of a component's passwords: kms → temp file → local config → kms (TESTSERVER-75/85/94)
#
# What for    The same file in every component's connect_external/kms/ (like kms_conf.sh); run through the
#             component's <short>_transfer_kms2tempfile.sh · _local2tempfile_random_value.sh · _tempfile2local.sh ·
#             _local2kms.sh. Every password line keeps its kms address in the comment right above it, in BOTH modes:
#                 # kms: ${KMS_URL}/v1/kv/data/mycache/redis          (odoo.conf: ; kms: …)
#                 REDIS_PASSWORD=${KMS_URL}/v1/kv/data/mycache/redis  ← kms   ·   REDIS_PASSWORD=<plain>  ← local
# How         python3 kms_transfer.py kms2file|random2file|file2conf|local2kms --mode-conf FILE --conf FILE …
#                     [--own-file F --shared-file F --by NAME]      (the temp-file ways need both files)
# Steps       kms2file    each password line's kms key read from kms → <entry>#<KEY>=<plain> in the component's own
#                         file; a key in SECRETS_SHARED_KEYS (used by 2+ components — svcmgt says) → the shared file
#                         (merged) · a key kms lacks → NOT_FOUND_IN_KMS · the config NOT changed · chmod 600 · needs kms
#             random2file the KEY NAMES only (the config's values are never read) → a new random value (32 letters/
#                         digits; *_API_KEY · *_TOKEN · SMTP_PASS → placeholder-<random>) for every key the files do
#                         not have yet — a key already there is kept · no kms, no login
#             file2conf   each password line ← its key from the own file, else the shared file · its "# kms:" comment
#                         kept (added when missing) · SECRET_MGT=local — the component runs WITHOUT kms · a line that
#                         would keep a kms address (its key in no file) → nothing changed at all · no kms
#             local2kms   SECRET_MGT already kms → nothing to do · each line under a "# kms:" comment: key missing in
#                         kms → added · different → kms updated (a new version) · the same → left · empty /
#                         NOT_FOUND_IN_KMS → not sent · a key another component sent first in this run (KMS_TRANSFER_SEEN)
#                         with a different value → not sent, WARN · the address back on the line · SECRET_MGT=kms
# Login       the kms owner (writing needs the owner; the agents can only read): KMS_TOKEN (handed over by
#             svcmgt/transfer_all_*.sh) · else KMS_MASTER_PASSWORD_FILE · else typed in a terminal · else one line, exit 1
# kms         KMS_URL from the caller · else the config's KMS_URL · that one not answering → http://127.0.0.1:8110 (kms on this PC)
# Output      values are never shown — only names, entries and counts; the last line:
#             [  OK  ] kms → local: 2 written · 0 not found in kms — SECRET_MGT=local
# ─────────────────────────────────────────────────────────────────────────────
import getpass, json, os, re, sys, tempfile, urllib.error, urllib.request

NOT_FOUND = "NOT_FOUND_IN_KMS"
SETTING = re.compile(r"^(\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*)(.*?)(\s*)$")
MARK = re.compile(r"^\s*([#;])\s*kms:\s*(\S+)\s*$")
ADDRESS = re.compile(r"^https?://[^/\s]+/v1/kv/data/([^#\s]+)(?:#([A-Za-z_][A-Za-z0-9_]*))?$")
LOCAL_PC = "http://127.0.0.1:8110"


def say(kind, msg):
    col = {"OK": "32", "INFO": "36", "WARN": "33", "ERROR": "31"}[kind]
    tag = {"OK": "[  OK  ]", "INFO": "[ INFO ]", "WARN": "[ WARN ]", "ERROR": "[ERROR] "}[kind]
    print(f"\033[{col}m{tag}\033[0m {msg}", flush=True)


def stop(msg):
    say("ERROR", msg)
    sys.exit(1)


def relined(ln, value):                                        # the same line with a new value, its line ending kept
    body = ln.rstrip("\r\n")
    m = SETTING.match(body)
    return f"{m.group(1)}{value}{m.group(4)}{ln[len(body):]}"


def setting(lines, name):
    for ln in reversed(lines):
        m = SETTING.match(ln)
        if m and m.group(2) == name:
            return m.group(3).strip().strip("\"'")
    return ""


def mode_of(lines):
    v = setting(lines, "SECRET_MGT").lower()
    if v in ("kms", "local"):
        return v
    if v:
        say("WARN", f"SECRET_MGT={v} is not known (kms · local) — taken as local")
    return "local"


def set_mode(lines, mode):
    for i, ln in enumerate(lines):
        m = SETTING.match(ln)
        if m and m.group(2) == "SECRET_MGT":
            lines[i] = relined(ln, mode)
            return
    at = next((i + 1 for i, ln in enumerate(lines) if (SETTING.match(ln) or [None] * 3)[2] == "KMS_URL"), len(lines))
    lines.insert(at, f"SECRET_MGT={mode}\n")


def base_of(lines):
    return setting(lines, "KMS_URL").rstrip("/")


def expand(value, base):
    return value.replace("${KMS_URL}", base)


def write(path, lines):                                        # the whole file at once, its permissions kept
    d = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".transfer-")
    with os.fdopen(fd, "w") as f:
        f.writelines(lines)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)


class Kms:
    def __init__(self, url, token):
        self.url, self.token = url, token

    def call(self, method, path, body=None):
        req = urllib.request.Request(f"{self.url}/v1/{path}", method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"X-Vault-Token": self.token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return {}
            stop(f"kms refused {method} {path.split('/', 2)[-1]} (HTTP {e.code}) — nothing changed in the config")

    def entry(self, e):
        return (self.call("GET", f"kv/data/{e}").get("data") or {}).get("data") or {}


def healthy(url):
    try:
        with urllib.request.urlopen(f"{url}/v1/sys/health", timeout=3) as r:
            return r.status == 200
    except Exception:
        return False


def kms_url(base):
    if os.environ.get("KMS_URL"):
        u = os.environ["KMS_URL"].rstrip("/")
        return u if healthy(u) else stop(f"kms at {u} is not running + unsealed — nothing changed")
    if base and healthy(base):
        return base
    if healthy(LOCAL_PC):
        say("INFO", f"kms at {base or '(no KMS_URL)'} does not answer from here — using kms on this PC ({LOCAL_PC})")
        return LOCAL_PC
    stop(f"kms is not running + unsealed ({base or 'no KMS_URL'} · {LOCAL_PC}) — nothing changed")


def owner_login(url):
    if os.environ.get("KMS_TOKEN"):
        say("INFO", "kms owner login: handed over")
        return os.environ["KMS_TOKEN"], False
    pwf, src, pw = os.environ.get("KMS_MASTER_PASSWORD_FILE", ""), "", ""
    if pwf and os.path.isfile(pwf) and open(pwf).read().strip():
        pw, src = open(pwf).readline().rstrip("\r\n"), "kms's master_password"
    else:
        try:
            with open("/dev/tty", "r+") as tty:
                pw, src = getpass.getpass(f"kms password for {os.environ.get('KMS_OWNER', 'nishan')} (hidden): ", stream=tty), "typed"
        except OSError:
            stop("no kms owner login — run it in a terminal (it asks your kms password), or "
                 "svcmgt/transfer_all_*.sh (one login from kms's master_password)")
    req = urllib.request.Request(f"{url}/v1/auth/userpass/login/{os.environ.get('KMS_OWNER', 'nishan')}", method="POST",
                                 data=json.dumps({"password": pw}).encode())
    del pw
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            tok = json.loads(r.read())["auth"]["client_token"]
    except Exception:
        stop(f"kms refused the owner login ({src}) — check it; nothing changed")
    say("INFO", f"kms owner login: from {src}")
    return tok, True


def items(files, base, want):
    """every password line under a "# kms:" comment: (file, index, name, address as written, entry, key, marked)"""
    out = []
    for path, lines in files.items():
        for i, ln in enumerate(lines):
            m = SETTING.match(ln.rstrip("\r\n"))
            if not m or m.group(2) in ("KMS_URL", "SECRET_MGT"):
                continue
            mark = MARK.match(lines[i - 1]) if i else None
            raw = mark.group(2) if mark else ""
            a = ADDRESS.match(expand(raw, base))
            if not a:
                continue
            out.append((path, i, m.group(2), raw, a.group(1), a.group(2) or m.group(2), bool(mark)))
    return out


def usage():                                                   # the header above, in colour
    n = 0
    for ln in open(__file__):
        if ln.startswith("# ─"):
            n += 1
            if n == 2:
                break
            continue
        if n == 1:
            t = ln[2:].rstrip("\n") if ln.startswith("# ") else ln[1:].rstrip("\n")
            head = t[:12]
            if re.match(r"^[A-Z][A-Za-z ]+$", head):
                print(f"\033[36m{head}\033[0m{t[12:]}")
            else:
                print(t if n != 1 or not t.startswith("kms_transfer.py") else f"\033[1m{t}\033[0m")


def keyed(files, base):
    """every password line with its kms key — from its "# kms:" comment, else from a kms address as its value:
    (file, index, name, address as written, entry, key)"""
    out = []
    for path, lines in files.items():
        for i, ln in enumerate(lines):
            m = SETTING.match(ln.rstrip("\r\n"))
            if not m or m.group(2) in ("KMS_URL", "SECRET_MGT"):
                continue
            mark = MARK.match(lines[i - 1]) if i else None
            for raw in ([mark.group(2)] if mark else []) + [m.group(3)]:
                a = ADDRESS.match(expand(raw, base))
                if a:
                    out.append((path, i, m.group(2), raw, a.group(1), a.group(2) or m.group(2)))
                    break
    return out


def read_secrets(path):
    """a hand-over file → ({"<entry>#<KEY>": value}, {"<entry>#<KEY>": "used by" text})"""
    vals, used, last = {}, {}, ""
    if not os.path.isfile(path):
        return vals, used
    for ln in open(path):
        ln = ln.rstrip("\r\n")
        if ln.startswith("# used by: "):
            last = ln[len("# used by: "):]
        elif ln and not ln.startswith("#") and "=" in ln:
            k, v = ln.split("=", 1)
            vals[k.strip()], used[k.strip()] = v, last
            last = ""
    return vals, used


def write_secrets(path, vals, used, title):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    out = [f"# secrets.conf — {title}: PLAIN passwords (TESTSERVER-85)\n",
           "# <kms entry>#<KEY>=<value> — <short>_transfer_tempfile2local.sh writes them into a SECRET_MGT=local config.\n",
           "# Temporary hand-over: remove it with  bash housekeeping/clean_temp.sh\n"]
    for k in sorted(vals):
        out += ["\n", f"# used by: {used.get(k, '')}\n", f"{k}={vals[k]}\n"]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".secrets-")
    with os.fdopen(fd, "w") as f:
        f.writelines(out)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def kms2file(files, base, own, shared_file, by):
    todo = keyed(files, base)
    if os.environ.get("SECRETS_LIST_KEYS"):                      # svcmgt asks which keys this component uses (no login)
        for k in dict.fromkeys(f"{t[4]}#{t[5]}" for t in todo):
            print(f"KEY {k}")
        return
    if not todo:
        stop(f"{' · '.join(os.path.basename(p) for p in files)}: no kms key on any password line — nothing to export")
    shared_keys = set(os.environ.get("SECRETS_SHARED_KEYS", "").split())
    url = kms_url(base)
    tok, mine = owner_login(url)
    kms = Kms(url, tok)
    try:
        cur = {e: kms.entry(e) for e in dict.fromkeys(t[4] for t in todo)}
    finally:
        if mine:
            try:
                kms.call("POST", "auth/token/revoke-self")
            except SystemExit:
                pass
    mine_v, mine_u = {}, {}
    sh_v, sh_u = read_secrets(shared_file)
    n_own = n_sh = missing = 0
    for path, i, name, raw, entry, key in todo:
        k = f"{entry}#{key}"
        val = cur[entry].get(key)
        if val is None:
            val, missing = NOT_FOUND, missing + 1
            say("WARN", f"{name} → {k}: not in kms — written as {NOT_FOUND}")
        if "\n" in val:
            stop(f"{name}: its kms value has a line break — a file line cannot hold it; nothing written")
        who = f"{by} {name}"
        if k in shared_keys:
            users = [u for u in (sh_u.get(k, "").split(" · ") if sh_u.get(k) else []) if u]
            if who not in users:
                users.append(who)
            sh_v[k], sh_u[k] = val, " · ".join(users)
            if k not in mine_v:
                n_sh += 1
        else:
            if k not in mine_v:
                n_own += 1
            users = [u for u in mine_u.get(k, "").split(" · ") if u]
            if who not in users:
                users.append(who)
            mine_v[k], mine_u[k] = val, " · ".join(users)
    write_secrets(own, mine_v, mine_u, by)
    if n_sh:
        write_secrets(shared_file, sh_v, sh_u, "keys used by 2+ components")
    say("OK", f"kms → file: {n_own} in its own file · {n_sh} in the shared file · {missing} not found in kms — "
              f"{own}{' + ' + shared_file if n_sh else ''} (chmod 600, the config unchanged)")


def file2conf(files, base, mode_conf, own, shared_file):
    if not os.path.isfile(own) and not os.path.isfile(shared_file):
        stop(f"no secrets file ({own} · {shared_file}) — make one first: <short>_transfer_kms2tempfile.sh "
             "or <short>_transfer_local2tempfile_random_value.sh")
    ov, _ = read_secrets(own)
    sv, _ = read_secrets(shared_file)
    todo, blocked = [], []
    for path, i, name, raw, entry, key in keyed(files, base):
        k = f"{entry}#{key}"
        val = ov.get(k, sv.get(k))
        now = SETTING.match(files[path][i].rstrip("\r\n")).group(3)
        if val is None or val == NOT_FOUND:
            if ADDRESS.match(expand(now, base)):
                blocked.append(name)                                   # it would stay a kms address in a local config
            else:
                say("WARN", f"{name} ← {k}: {'not in the file' if val is None else NOT_FOUND} — its local value kept")
            continue
        if "\n" in val:
            stop(f"{name}: its value in the file has a line break — a config line cannot hold it; nothing changed")
        todo.append((path, i, name, raw, k, val, now))
    if blocked:
        stop(f"{', '.join(blocked)}: not in the file — their lines still hold kms addresses; nothing changed "
             "(fill the file first: <short>_transfer_kms2tempfile.sh or <short>_transfer_local2tempfile_random_value.sh)")
    written = same = 0
    for path, i, name, raw, k, val, now in sorted(todo, key=lambda t: (t[0], -t[1])):   # bottom-up: inserts keep indexes
        lines = files[path]
        if now == val:
            same += 1
        else:
            lines[i] = relined(lines[i], val); written += 1
            say("OK", f"{name} ← {k}: written from the {'own' if k in ov else 'shared'} file")
        if not (i and MARK.match(lines[i - 1])):                       # keep the kms address in its comment
            lines.insert(i, f"{';' if any(l.startswith('[') for l in lines) else '#'} kms: {raw}\n")
    was = mode_of(files[mode_conf])
    set_mode(files[mode_conf], "local")
    for p, lines in files.items():
        write(p, lines)
    missing = len(keyed(files, base)) - len(todo)
    say("OK", f"file → local: {written} written · {same} the same · {missing} not in the file — SECRET_MGT=local"
              f"{' (was ' + was + ')' if was != 'local' else ''}; runs WITHOUT kms now (git: commit/push for this repo defaults to no)")
    if not os.environ.get("SECRETS_NO_REMINDER"):
        say("INFO", "the plain files are still in mountspace/temp — remove them when done: bash housekeeping/clean_temp.sh")


def random2file(files, base, own, shared_file, by):
    import secrets as _s, string as _st
    todo = keyed(files, base)
    if os.environ.get("SECRETS_LIST_KEYS"):                      # svcmgt asks which keys this component uses (no login)
        for k in dict.fromkeys(f"{t[4]}#{t[5]}" for t in todo):
            print(f"KEY {k}")
        return
    if not todo:
        stop(f"{' · '.join(os.path.basename(p) for p in files)}: no “# kms:” key on any password line — nothing to fill")
    shared_keys = set(os.environ.get("SECRETS_SHARED_KEYS", "").split())
    outside = lambda key: key.endswith("_API_KEY") or key.endswith("_TOKEN") or key == "SMTP_PASS"
    rand = lambda: "".join(_s.choice(_st.ascii_letters + _st.digits) for _ in range(32))
    ov, ou = read_secrets(own)
    sv, su = read_secrets(shared_file)
    made = kept = 0
    for path, i, name, raw, entry, key in todo:                  # KEY NAMES only — the config's values are never read
        k, who = f"{entry}#{key}", f"{by} {name}"
        v, u = (sv, su) if k in shared_keys else (ov, ou)
        if k in shared_keys and k not in sv and k in ov:          # it became shared → moved to the shared file
            sv[k], su[k] = ov.pop(k), ou.pop(k, "")
        if v.get(k) not in (None, NOT_FOUND):
            kept += 1                                            # never overwritten: a second run changes nothing
        else:
            v[k] = ("placeholder-" + rand()) if outside(key) else rand(); made += 1
            say("OK" if not outside(key) else "WARN", f"{name} → {k}: " + ("a placeholder — put your real one in the file"
                if outside(key) else "a new random value"))
        users = [x for x in u.get(k, "").split(" · ") if x]
        if who not in users:
            users.append(who)
        u[k] = " · ".join(users)
    write_secrets(own, ov, ou, by)
    if sv:
        write_secrets(shared_file, sv, su, "keys used by 2+ components")
    say("OK", f"random → file: {made} new · {kept} already there (kept) — {own}{' + ' + shared_file if sv else ''} "
              "(chmod 600, no kms, the config unchanged; values never shown)")


def main(argv):
    if argv and argv[0] in ("-h", "--help"):
        usage()
        return 0
    if not argv or argv[0] not in ("local2kms", "kms2file", "file2conf", "random2file"):
        print("usage: kms_transfer.py local2kms|kms2file|file2conf|random2file --mode-conf FILE --conf FILE …  (run through the component's scripts)")
        return 2
    way, mode_conf, confs, own, shared_file, by, i = argv[0], None, [], "", "", "", 1
    while i < len(argv):
        if argv[i] == "--mode-conf":
            mode_conf = argv[i + 1]; i += 2
        elif argv[i] == "--conf":
            confs.append(argv[i + 1]); i += 2
        elif argv[i] == "--own-file":
            own = argv[i + 1]; i += 2
        elif argv[i] == "--shared-file":
            shared_file = argv[i + 1]; i += 2
        elif argv[i] == "--by":
            by = argv[i + 1]; i += 2
        else:
            stop(f"unknown argument {argv[i]}")
    for p in [mode_conf] + confs:
        if not p or not os.path.isfile(p):
            stop(f"config not found: {p} — nothing changed")
    files = {p: open(p).readlines() for p in dict.fromkeys([mode_conf] + confs)}
    names = " · ".join(os.path.basename(p) for p in files)
    mode, base = mode_of(files[mode_conf]), base_of(files[mode_conf])
    if way in ("kms2file", "file2conf", "random2file"):
        if not own or not shared_file:
            stop("--own-file and --shared-file are needed")
        who = by or os.path.basename(os.path.dirname(mode_conf))
        {"kms2file": lambda: kms2file(files, base, own, shared_file, who),
         "file2conf": lambda: file2conf(files, base, mode_conf, own, shared_file),
         "random2file": lambda: random2file(files, base, own, shared_file, who)}[way]()
        return 0
    if mode == "kms":
        say("OK", f"local → kms: already SECRET_MGT=kms in {os.path.basename(mode_conf)} — nothing to do")
        return 0

    todo = items(files, base, way)
    if not todo:
        stop(f"{names}: no “# kms: <address>” comment above a password — "
             "nothing tells where the passwords live in kms; nothing changed")
    url = kms_url(base)
    tok, mine = owner_login(url)
    kms = Kms(url, tok)
    try:
        cur = {e: kms.entry(e) for e in dict.fromkeys(t[4] for t in todo)}
        changes, added, updated, same, unsent = {}, 0, 0, 0, 0
        seen_f = os.environ.get("KMS_TRANSFER_SEEN", "")             # svcmgt/transfer_all_local2kms.sh: keys sent this run
        seen = set(open(seen_f).read().split()) if seen_f and os.path.isfile(seen_f) else set()
        for path, i, name, raw, entry, key, _ in todo:
            val = SETTING.match(files[path][i].rstrip("\r\n")).group(3)
            if len(val) > 1 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]                                          # "quoted" in the config → the value inside
            kv = cur[entry]
            if ADDRESS.match(expand(val, base)):
                same += 1; continue                                      # already an address (half-done earlier run)
            if val in ("", NOT_FOUND):
                unsent += 1
                say("WARN", f"{name}: {'empty' if not val else NOT_FOUND} — not sent to kms (kms keeps {'its value' if key in kv else 'no value — kms-keys creates one'})")
                continue
            if f"{entry}#{key}" in seen and kv.get(key) != val:           # another component sent it first in this run
                unsent += 1
                say("WARN", f"{name} → kv/{entry}: another component already sent a different value in this run — this local "
                            "value is NOT sent; check which one is right (kms UI)")
                continue
            if key not in kv:
                changes.setdefault(entry, {})[key] = val; added += 1
                say("OK", f"{name} → kv/{entry}: added to kms")
            elif kv[key] != val:
                changes.setdefault(entry, {})[key] = val; updated += 1
                say("OK", f"{name} → kv/{entry}: kms updated from the local value")
            else:
                same += 1
        for entry, new in changes.items():                          # one write per entry, its other keys kept
            md = kms.call("GET", f"kv/metadata/{entry}").get("data") or {}
            before = str(md.get("current_version", ""))
            ver = (kms.call("POST", f"kv/data/{entry}", {"data": {**cur[entry], **new}}).get("data") or {}).get("version")
            note = dict(md.get("custom_metadata") or {})
            for k in new:
                note.pop(f"initial_{k}", None)                     # a real value now — kms's secret_age.sh stops listing it
            for k, v in list(note.items()):
                f = (v or "").split(";")
                if k.startswith("initial_") and len(f) == 4 and f[1] == f"v{before}":
                    note[k] = ";".join([f[0], f"v{ver}", f[2], f[3]])
            if note != (md.get("custom_metadata") or {}):
                kms.call("POST", f"kv/metadata/{entry}", {"custom_metadata": note})
        if seen_f:
            with open(seen_f, "a") as f:
                f.write("".join(f"{e}#{k}\n" for e, new in changes.items() for k in new))
        for path, i, name, raw, entry, key, _ in todo:
            files[path][i] = relined(files[path][i], raw)
        set_mode(files[mode_conf], "kms")
        for p, lines in files.items():
            write(p, lines)
        say("OK", f"local → kms: {added} added · {updated} updated · {same} the same · {unsent} not sent — SECRET_MGT=kms; "
                  f"{names} hold kms addresses again")
    finally:
        if mine:
            try:
                kms.call("POST", "auth/token/revoke-self")
            except SystemExit:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
