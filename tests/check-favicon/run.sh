#!/usr/bin/env bash
#
# Selbsttest für check-favicon.
#
# legt ein temporäres Verzeichnis an, erzeugt darin die Fixture-Seiten, startet
# für jeden Fall einen lokalen Server, fährt das Script gegen die lokale URL und
# prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-favicon"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

PIDS=()
fail=0

cleanup_servers() {
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup_servers EXIT

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
    case "$exp_rc" in
        ''|*[!0-9]*) echo "FEHLER: expect ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;;
    esac
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
    local kw="$1"
    if printf '%s' "$OUT" | grep -qF -- "$kw"; then
        echo "FEHLER: Stichwort „$kw” war unerwartet in der Ausgabe" >&2
        fail=1
    fi
}

# Fixtures erzeugen
python3 "$HERE/make_fixtures.py" "$WORK" >/dev/null

# --- komplett: alles korrekt, keine Befunde, keine Hinweise ----------------
port="$(start_server "$WORK/komplett")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde."
expect_not "Hinweis"

# --- inline-svg: Icon als data:-URI zählt als SVG-Icon, nicht als externer Host
port="$(start_server "$WORK/inline-svg")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde." "Inline-Icon (SVG)"
expect_not "externer Host"
expect_not "kein SVG-Icon"

# --- nichts: nur index.html, keine Links, keine Dateien --------------------
port="$(start_server "$WORK/nichts")"
run_script "http://127.0.0.1:$port"
expect 1 "/favicon.ico fehlt" 'kein <link rel="icon">' "apple-touch-icon" "manifest"

# --- falsch: Größen, 404, apple-touch-icon, Manifest -----------------------
port="$(start_server "$WORK/falsch")"
run_script "http://127.0.0.1:$port"
expect 1 "die Datei ist aber 64×64" "HTTP 404" "57×57" "kein Icon 512×512"

# --- ohne-extras: wie komplett, aber ohne SVG und maskable ------------------
port="$(start_server "$WORK/ohne-extras")"
run_script "http://127.0.0.1:$port"
expect 0 "kein SVG-Icon" "maskable" "kein 32×32"

# --- kaputtes-manifest: Manifest ist kein JSON ------------------------------
port="$(start_server "$WORK/kaputtes-manifest")"
run_script "http://127.0.0.1:$port"
expect 1 "kein gültiges JSON"

# --- nicht erreichbar: Port ohne Server -------------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# --- Nutzungsfehler: kein Argument -----------------------------------------
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
