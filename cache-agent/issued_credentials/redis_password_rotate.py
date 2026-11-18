#!/usr/bin/env python3
"""redis_password_rotate.py — the fix for the reminder: the Redis password gets a new random value (kms + Redis).

The door: redis_password_rotate.sh (its --help). The work is mycache's existing rotation, nothing copied:
../connect_external/kms/refresh_random_secrets_to_kms.sh, then the reminder again (the new date).
NO mirror log on purpose: the refresh reads the owner's kms password.
"""
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path[:0] = [str(p / "ccc/scripts/lib/python_starter") for p in HERE.parents if (p / "mountspace").is_dir()][:1]
try:
    import starter
    if sys.argv[1:2] in (["-h"], ["--help"]):
        print(starter.header_help(os.environ.get("STARTER", "")))
        sys.exit(0)
except ImportError:
    pass

rc = subprocess.run(["bash", str(HERE.parent / "connect_external/kms/refresh_random_secrets_to_kms.sh"),
                     *sys.argv[1:]]).returncode
if rc:
    sys.exit(rc)
sys.exit(subprocess.run(["bash", str(HERE / "redis_password_rotation_check.sh")]).returncode)
