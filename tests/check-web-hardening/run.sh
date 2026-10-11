#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../../claude/skills/code-quality/bin/check-web-hardening"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/curl" <<'SH'
#!/usr/bin/env bash
headers=""; body=""; format=""; url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -D|-o|-w|-H) key="$1"; shift; case "$key" in -D) headers="$1";; -o) body="$1";; -w) format="$1";; esac ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
if [ -n "$headers" ]; then
    {
        printf 'HTTP/1.1 200 OK\r\nStrict-Transport-Security: max-age=31536000\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: strict-origin\r\nX-Frame-Options: DENY\r\nPermissions-Policy: geolocation=()\r\n'
        [ ! -s "$MOCK_POLICY" ] || printf 'Content-Security-Policy: %s\r\n' "$(cat "$MOCK_POLICY")"
        printf '\r\n'
    } > "$headers"
fi
if [ -n "$body" ] && [ "$body" != /dev/null ]; then
    if [[ "$url" == */robots.txt ]]; then
        printf 'User-agent: *\nAllow: /\n' > "$body"
    else
        printf '<html><body>OK</body></html>' > "$body"
    fi
fi
case "$format" in
    *size_download*) printf '200 0' ;;
    *) printf '200' ;;
esac
SH
chmod +x "$TMP/curl"
export MOCK_POLICY="$TMP/policy"
export PATH="$TMP:$PATH"

: > "$MOCK_POLICY"
OUT="$("$CHECK" https://example.test)"
[[ "$OUT" == *"Content-Security-Policy fehlt"* ]]

printf "default-src 'self'; script-src 'unsafe-inline'\n" > "$MOCK_POLICY"
OUT="$("$CHECK" https://example.test)"
[[ "$OUT" == *"erlaubt 'unsafe-inline'"* ]]

printf "img-src 'self'\n" > "$MOCK_POLICY"
OUT="$("$CHECK" https://example.test)"
[[ "$OUT" == *"ohne script-src/default-src"* ]]

printf "default-src 'self'; script-src 'self'\n" > "$MOCK_POLICY"
OUT="$("$CHECK" https://example.test)"
[[ "$OUT" != *"Content-Security-Policy fehlt"* ]]
[[ "$OUT" != *"erlaubt 'unsafe-inline'"* ]]

echo "OK: CSP-Hinweise bestanden"
