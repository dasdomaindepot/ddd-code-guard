#!/usr/bin/env bash
#
# Selbsttest für check-web-resources.
#
# legt ein temporäres Verzeichnis an, erzeugt darin die Fixture-Seiten, startet
# für jeden Fall einen lokalen Server, fährt das Script gegen die lokale URL und
# prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-web-resources"

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
    python3 "$HERE/server.py" "$port" "$dir" >/dev/null 2>&1 &
    pid=$!
    PIDS+=("$pid")
    wait_port "$port" || { echo "FEHLER: Server für $dir antwortet nicht" >&2; exit 1; }
    printf '%s' "$port"
}

RC=0
OUT=""
fail=0

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

# --- gut: alles korrekt, keine Befunde, keine Hinweise ----------------------
port="$(start_server "$WORK/gut")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde."
expect_not "Hinweis"

# --- kaputt: kaputter Link (2 Seiten) und kaputter Bild ---------------------
port="$(start_server "$WORK/kaputt")"
run_script "http://127.0.0.1:$port"
expect 1 "2 Befund(e)." "Link auf /gibt-es-nicht liefert HTTP 404" "auch auf 1 weiteren Seite" "Bild /fehlt.png liefert HTTP 404"

# hinweise: Redirect-Kette, Bild ohne Maße, großes PNG, externes Skript ------
port="$(start_server "$WORK/hinweise")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde." "leitet über 3 Stationen weiter" "ohne Maße" "ohne integrity" "blockiert das Rendern" "WebP oder AVIF" "KB — komprimieren"

# MAX_RESOURCES: Überlauf der Zielen-Anzahl erzeugt den Hinweis --------------
port="$(start_server "$WORK/hinweise")"
MAX_RESOURCES=2 run_script "http://127.0.0.1:$port"
expect 0 "von 3 Zielen geprüft (MAX_RESOURCES)"

# toolbar: Symfony-Toolbar wird ignoriert ------------------------------------
port="$(start_server "$WORK/toolbar")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde."
expect_not "/_kaputt"
expect_not "nix.png"

# nicht erreichbar: Port ohne Server -----------------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# Nutzungsfehler: kein Argument ----------------------------------------------
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
