#!/usr/bin/env python3
"""pod.py — what mycache's lifecycle programs share (start · stop · status · state · ensure_* · destroy · logs · login).

    POD        this pod's folder (projectspace/platform/mycache) — every program works from here, as the bash did (cd)
    WS_ROOT    the workspace: the first folder upwards that holds mountspace/ ("/" when none, as the bash loop)
    starter    ccc's python_starter (--help from the door's header + the mirror log) — None in a temp copy
    help_only()                   --help for a program that keeps NO mirror log (state · host_status …)
    running(name)                 is that container running?          (docker ps --filter status=running)
    docker(*args, quiet=False)    run docker from POD → its exit code (quiet = its output not shown, as >/dev/null 2>&1)
    ok / info / err / die         the coloured lines the bash printed

Run alone it prints WS_ROOT — start.sh's guard line uses it (the guard stays in the door: test_move_repos M6 reads it).
Standard library only.
"""
import os
import pathlib
import subprocess
import sys

POD = pathlib.Path(__file__).resolve().parent.parent
WS_ROOT = next((str(p) for p in POD.parents if (p / "mountspace").is_dir()), "/")
sys.path[:0] = [str(pathlib.Path(WS_ROOT) / "ccc/scripts/lib/python_starter")]
try:
    import starter
except ImportError:                       # outside a workspace (a temp copy): no --help, no mirror log — as the bash
    starter = None

GREEN, RED, YELLOW, CYAN, BOLD, OFF = "\033[32m", "\033[31m", "\033[33m", "\033[36m", "\033[1m", "\033[0m"


def ok(text):
    print(f"{GREEN}[  OK  ]{OFF} {text}", flush=True)


def info(text):
    print(f"{CYAN}[ INFO ]{OFF} {text}", flush=True)


def err(text):
    print(f"{RED}[ERROR]{OFF}  {text}", flush=True)


def die(text):
    err(text)
    sys.exit(1)


def help_only():
    """-h / --help → the door's header, exit 0. For the programs that keep no mirror log."""
    if starter and sys.argv[1:2] in (["-h"], ["--help"]):
        print(starter.header_help(os.environ.get("STARTER", "")))
        sys.exit(0)


def docker(*args, quiet=False):
    """docker <args> from the pod's folder → exit code. quiet=True hides its output (the bash's >/dev/null 2>&1)."""
    out = subprocess.DEVNULL if quiet else None
    return subprocess.run(["docker", *args], cwd=POD, stdout=out, stderr=out).returncode


def names(*ps_args):
    """The container names `docker ps <ps_args> --format {{.Names}}` lists ([] when docker does not answer)."""
    r = subprocess.run(["docker", "ps", *ps_args, "--format", "{{.Names}}"], cwd=POD,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return r.stdout.split()


def running(name):
    return name in names("--filter", "status=running")


def door(name, *args):
    """Run another door of this pod (bash <name> <args>) — as the bash did → its exit code."""
    return subprocess.run(["bash", str(POD / name), *args], cwd=POD).returncode


if __name__ == "__main__":
    print(WS_ROOT)
