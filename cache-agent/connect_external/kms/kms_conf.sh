# ─────────────────────────────────────────────────────────────────────────────
# kms_conf.sh — SOURCED by the kms scripts here: the cache-agent's config lines with ${KMS_URL} expanded (TESTSERVER-46)
#
# What for    agent.conf names kms's base ONCE (KMS_URL=http://kms-openbao:8200); every secret is
#             ${KMS_URL}/v1/kv/data/<entry>[#KEY]. The Python agent's dotenv expands it by itself; the shell
#             scripts read the lines through this one function. A line written in full (http://…) works as before.
# How         source "$HERE/kms_conf.sh"
#             kms_conf FILE   → every KEY=value line (no comments), ${KMS_URL} replaced by the file's KMS_URL
#             kms_base FILE   → kms's base: the file's KMS_URL, else the first full address on a setting line
# ─────────────────────────────────────────────────────────────────────────────
kms_base() {
    local b
    b="$(grep -E '^KMS_URL=' "$1" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's#/*$##')"
    [ -n "$b" ] || b="$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=https?://' "$1" 2>/dev/null | grep -oE 'https?://[^/ ]+' | head -1)"
    printf '%s' "$b"
}
kms_conf() {
    local b; b="$(kms_base "$1")"
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null | sed "s#\${KMS_URL}#${b}#g"
}
