#!/usr/bin/env bash
#
# Selbsttest für check-form-protection.
#
# Startet für jeden Fixture-Ordner einen lokalen Server, fährt das Script gegen
# die lokale URL und prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-form-protection"

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

# --- Regression: Registrierung mit nur E-Mail + einem Passwort, Honeypot mit
# -500px, verstecktes Feld mit "mail" im Login-Formular
port="$(start_server "$HERE/fixtures/regression")"
run_script "http://127.0.0.1:$port"
expect 1 "/registrieren" "(Registrierung) ohne Honeypot" "/kontakt" "nur mit Honeypot"
expect_not "Formular /login"

# --- ungeschützt: Kontaktformular ohne Schutz ---------------------------
port="$(start_server "$HERE/fixtures/ungeschuetzt")"
run_script "http://127.0.0.1:$port"
expect 1 "ohne Honeypot oder Captcha" "/kontakt"

# --- nur Honeypot: Hinweis plus Block zusätzlichem Schutz --------------
port="$(start_server "$HERE/fixtures/nur-honeypot")"
run_script "http://127.0.0.1:$port"
expect 0 "nur mit Honeypot" "ALTCHA"

# --- Honeypot plus Zeitsperre: geschützt, kein „nur mit Honeypot" ------
port="$(start_server "$HERE/fixtures/honeypot-zeit")"
run_script "http://127.0.0.1:$port"
expect 0 "geschützt"
expect_not "nur mit Honeypot"

# --- Captcha (ALTCHA) auf Registrierungsformular -----------------------
port="$(start_server "$HERE/fixtures/altcha")"
run_script "http://127.0.0.1:$port"
expect 0 "geschützt"

# --- offene Registrierung: Befund --------------------------------------
port="$(start_server "$HERE/fixtures/registrierung-offen")"
run_script "http://127.0.0.1:$port"
expect 1 "(Registrierung)"

# --- nur Login- und Suchformular: kein öffentliches Formular ----------
port="$(start_server "$HERE/fixtures/nur-login")"
run_script "http://127.0.0.1:$port"
expect 0 "kein öffentliches"

# --- Honeypot über style-Attribut --------------------------------------
port="$(start_server "$HERE/fixtures/style-honeypot")"
run_script "http://127.0.0.1:$port"
expect 0 "nur mit Honeypot"

# --- nicht erreichbar: Port ohne Server ----------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# --- Nutzungsfehler: kein Argument --------------------------------------
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
