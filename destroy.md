# destroy.sh — ⚠️ Stop mycache AND delete all its data (full reset).

**Who runs it:** You only, on purpose.

**How to run it** — from the mycache folder:
```
$ cd ~/myworkspace/projectspace/mycache
$ bash destroy.sh
(asks to confirm, then removes containers + the data volume)
```

**What it does:**
1. `docker compose down -v --remove-orphans` — the cached data is gone for good

**Next / errors:** Plane loses its cache too (it rebuilds). Secrets in kms are not touched.
