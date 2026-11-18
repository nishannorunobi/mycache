# issued_credentials — the keys mycache ISSUES (it is the server): reminders before they need you (CONFMGT [8.6])

| door | .py | what |
|---|---|---|
| `credentials_check.sh` | `credentials_check.py` | runs every `*_check.sh` here with `--quiet` — silent while fine, the mirror log always · exit = the worst (start.sh / stop.sh never stop for it) |
| `redis_password_rotation_check.sh [--quiet]` | `redis_password_rotation_check.py` | the 90-day reminder for the Redis password (the date from kms, mycache's own login) |
| `redis_password_rotate.sh` | `redis_password_rotate.py` | the fix: `../connect_external/kms/refresh_random_secrets_to_kms.sh`, then the reminder again (no mirror log: it reads the owner's kms password) |
| `credentials.conf` | — | WARN_BEFORE_DAYS=7 · ROTATE_AFTER_DAYS=90 (written by confmgt) |

A new key = a new `<key>_rotation_check.sh` + `.py` here — found by itself.
Test: `bash ~/myworkspace/projectspace/platform/mycache/cache-agent/issued_credentials/test_credentials.sh` → C0–C7 L1 on a throwaway kms (:8122), old bash = new.
