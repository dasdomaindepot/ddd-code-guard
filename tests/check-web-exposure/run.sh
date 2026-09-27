#!/usr/bin/env bash
#
# Selbsttest für check-web-exposure.
#
# startet für jeden Fall einen lokalen Testserver (server.py <port> <fall>),
# fährt das Script gegen die lokale URL und prüft Exit-Code und Ausgabe.
# Zusätzlich werden die reinen Funktionen cookie_problems() und
# check_redirect() direkt aufgerufen. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-web-exposure"

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
    local fall="$1" port pid
    port="$(free_port)"
    python3 "$HERE/server.py" "$port" "$fall" >/dev/null 2>&1 &
    pid=$!
    PIDS+=("$pid")
    wait_port "$port" || { echo "FEHLER: Server für Fall $fall antwortet nicht" >&2; exit 1; }
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
    local kw
    for kw in "$@"; do
        if printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw” war unerwartet in der Ausgabe" >&2
            fail=1
        fi
    done
}

# --- sauber: alles korrekt, keine Befunde ----------------------------------
port="$(start_server "sauber")"
run_script "http://127.0.0.1:$port"
expect 0 "Keine Befunde." "keine geheimen Dateien" "liefert 404"

# --- leck: Geheimdateien + 500 + Stacktrace --------------------------------
port="$(start_server "leck")"
run_script "http://127.0.0.1:$port"
expect 1 "/.env wird ausgeliefert" "/.git/HEAD wird ausgeliefert" "HTTP 500 statt 404" "Stacktrace"

# --- spa: identische Seiten für jeden Pfad ---------------------------------
port="$(start_server "spa")"
run_script "http://127.0.0.1:$port"
expect 0 "SPA-Fallback"
expect_not "wird ausgeliefert"

# --- debug: X-Debug-Token, kein Stacktrace-Befund --------------------------
port="$(start_server "debug")"
run_script "http://127.0.0.1:$port"
expect 1 "Debug-Modus"
expect_not "zeigt einen Stacktrace"

# --- cookies: fehlende Flags -----------------------------------------------
port="$(start_server "cookies")"
run_script "http://127.0.0.1:$port"
expect 1 "ohne HttpOnly" "ohne SameSite"
expect_not "main_deauth_profile_token" "main_auth_profile_token"

# --- cors: offene Credentials ----------------------------------------------
port="$(start_server "cors")"
run_script "http://127.0.0.1:$port"
expect 1 "jede Herkunft"

# --- ohne Server: nicht messbar --------------------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# --- Nutzungsfehler: kein Argument -----------------------------------------
run_script
expect 2

# --- reine Funktionen: Cookie-Auswertung und Umleitung ---------------------
if ! python3 - "$SCRIPT" <<'PY'
import importlib.machinery, sys
m = importlib.machinery.SourceFileLoader("cwe", sys.argv[1]).load_module()
p = m.cookie_problems("PHPSESSID=a; Path=/; HttpOnly; SameSite=Lax", True)
assert any("Secure" in s for s in p), p
k, _ = m.check_redirect(301, "https://x/")
assert k == "ok", k
k, _ = m.check_redirect(302, "https://x/")
assert k == "hint", k
k, _ = m.check_redirect(200, "")
assert k == "finding", k
print("OK: pure-Funktionen")
PY
then
    echo "FEHLER: pure Funktionen haben nicht bestanden" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
