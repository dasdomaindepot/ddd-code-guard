#!/usr/bin/env bash
#
# Selbsttest für check-third-party.
#
# Startet für jeden Fixture-Ordner einen lokalen Server, fährt das Script gegen
# die lokale URL und prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-third-party"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

PIDS=()
fail=0

cleanup() {
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

wait_port() {
    local port="$1" i
    for i in $(seq 1 50); do
        if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(0.2); sys.exit(0 if s.connect_ex(('127.0.0.1',$port))==0 else 1)"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

start_server() {
    local dir="$1" port pid
    port="$(free_port)"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
    pid=$!
    PIDS+=("$pid")
    wait_port "$port" || { echo "FEHLER: Server für $dir antwortet nicht" >&2; exit 1; }
    printf '%s' "$port"
}

RC=0
OUT=""

run_script() {
    if OUT="$("$SCRIPT" "$@" 2>&1)"; then
        RC=0
    else
        RC=$?
    fi
}

expect() {
    local exp_rc="$1"; shift
    local ok=1 kw
    if [ "$RC" -ne "$exp_rc" ]; then
        echo "FEHLER: erwarteter Exit $exp_rc, aber $RC" >&2
        printf '%s\n' "$OUT" >&2
        ok=0
    fi
    for kw in "$@"; do
        if ! printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw” nicht in der Ausgabe" >&2
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] || fail=1
}

expect_not() {
    local kw
    for kw in "$@"; do
        if printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw“ unerwartet in der Ausgabe" >&2
            fail=1
        fi
    done
}

# --- guter Fall: youtube-nocookie, selbst gehosteter Schrift, kein Tracker ----------
port="$(start_server "$HERE/fixtures/gut")"
run_script "http://127.0.0.1:$port"
expect 0 "keine Drittanbieter beim ersten Aufruf"

# --- Google Fonts direkt über <link> ------------------------------------------------
port="$(start_server "$HERE/fixtures/fonts")"
run_script "http://127.0.0.1:$port"
expect 1 "Google Fonts"

# --- Google Fonts über verlinktes Stylesheet (@import) ------------------------------
port="$(start_server "$HERE/fixtures/fonts-css")"
run_script "http://127.0.0.1:$port"
expect 1 "über /app.css"

# --- Tracker ohne Consent: Analytics, YouTube, Maps ---------------------------------
port="$(start_server "$HERE/fixtures/tracker")"
run_script "http://127.0.0.1:$port"
expect 1 \
    "Google Analytics/Tag Manager" \
    "YouTube ohne youtube-nocookie.com" \
    "Google Maps"

# --- Consent-Tool erkannt: alle zu Hinweisen, kein Befund ---------------------------
port="$(start_server "$HERE/fixtures/consent")"
run_script "http://127.0.0.1:$port"
expect 0 "Consent-Tool erkannt"
expect_not "ohne Einwilligung"

# --- blockiert (data-src / type=text/plain): nichts wird geladen ---------------------
port="$(start_server "$HERE/fixtures/blockiert")"
run_script "http://127.0.0.1:$port"
expect 0

# --- externes CDN: nur Hinweis, kein Befund -----------------------------------------
port="$(start_server "$HERE/fixtures/cdn")"
run_script "http://127.0.0.1:$port"
expect 0 "externes CDN"

# --- nicht erreichbar: Port ohne Server ----------------------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# --- Nutzungsfehler: kein Argument --------------------------------------------------
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
