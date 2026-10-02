# add_secret_to_kms.sh — a NEW secret for the mycache Redis server → kms

**What for:** a new password / key / token for mycache goes into **kms**, never into `.env` or
any config file.

**Who runs it:** the kms owner (needs the kms password). mycache itself may only read.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash connect_external/kms/add_secret_to_kms.sh NEW_API_KEY
kms password for nishan (hidden): ********
Value for NEW_API_KEY (hidden): ********
[  OK  ] kv/mycache/redis  NEW_API_KEY stored (version 3) — read it with: kms_get mycache-redis mycache/redis NEW_API_KEY
```
The same command with an existing key name **changes** its value (kms keeps old versions).

**What it does:** stores the value in `kv/mycache/redis`; the keys already there are kept; nothing
is printed except the version number.

**Next — use it in the code**, one line in `start.sh`, next to the existing one:
```bash
kms_get mycache-redis mycache/redis REDIS_PASSWORD NEW_API_KEY || exit 1
```
No new sign-up needed: `mycache-redis` can already read `kv/mycache/redis`.
