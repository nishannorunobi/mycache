#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# mycache_container_login.sh — a shell INSIDE mycache's running container, to look around (MYCACHE)
#
# What for    One command instead of remembering: docker exec -it <container> bash|sh. A container has no SSH
#             and no login prompt — this is the way in. Type exit to come back; the container keeps running.
# Steps       1. the container: mycache-redis (the default)
#                or another one as the argument: mycache-redis-ui
#             2. checks it runs (else: how to start it)
#             3. a short reminder, then the shell — bash if the image has it, else sh
# How         bash ~/myworkspace/projectspace/mycache/mycache_container_login.sh          (or: … mycache-redis-ui)
# Careful     the Redis data is REAL (Plane's cache and queues) — look, do not change.
# See also    a single command without a shell: docker exec mycache-redis <command>
# ─────────────────────────────────────────────────────────────────────────────
case "${1:-}" in -h|--help) sed -n '3,/^# ─/{/^# ─/d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;; esac
set -uo pipefail
# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then source "$_WS_ROOT/init/create_logging_path.sh"; setup_logging; fi
# ──────────────────────────────────────────────────────────────────────────────
ok()   { echo -e "\033[32m[  OK  ]\033[0m $*"; }
info() { echo -e "\033[36m[ INFO ]\033[0m $*"; }
die()  { echo -e "\033[31m[ERROR]\033[0m  $*"; exit 1; }
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/." && pwd)"
CONTAINERS=(mycache-redis mycache-redis-ui)
C="${1:-mycache-redis}"
[[ " ${CONTAINERS[*]} " == *" $C "* ]] || die "'$C' is not one of mycache's containers: ${CONTAINERS[*]}"
docker info >/dev/null 2>&1 || die "Docker is not running (or this login is not in the docker group yet)"
[ -n "$(docker ps -q -f "name=^$C\$")" ] || die "$C is not running — start it: bash $PROJECT_DIR/ensure_running.sh"
{ : </dev/tty; } 2>/dev/null || die "this needs a terminal (run it yourself, not from another script)"
docker exec "$C" sh -c 'command -v bash' >/dev/null 2>&1 && SH=bash || SH=sh
ok "entering $C ($SH) — exit = back here, the container keeps running"
info "careful: the Redis data is REAL (Plane's cache and queues)"
# The session itself is NOT mirror-logged: the log pipe is not a terminal (no prompt, no keys) and would record
# everything typed — the shell gets the real terminal back.
exec </dev/tty >/dev/tty 2>&1
exec docker exec -it "$C" "$SH"
