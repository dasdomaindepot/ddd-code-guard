#!/usr/bin/env bash
#
# Selbsttest für check-app-static.
#
# Fährt das Script für jeden Fixture-Ordner direkt (ein Verzeichnis als
# Argument; es wird nichts gestartet oder aufgerufen) und prüft Exit-Code
# und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-app-static"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

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
        ''|*[!0-9]*) echo "FEHLER: ${FUNCNAME[0]} ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;;
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
    local exp_rc="$1"; shift
    case "$exp_rc" in
        ''|*[!0-9]*) echo "FEHLER: ${FUNCNAME[0]} ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;;
    esac
    local ok=1 kw
    if [ "$RC" -ne "$exp_rc" ]; then
        echo "FEHLER: erwarteter Exit $exp_rc, aber $RC" >&2
        printf '%s\n' "$OUT" >&2
        ok=0
    fi
    for kw in "$@"; do
        if printf '%s' "$OUT" | grep -qF -- "$kw"; then
            echo "FEHLER: Stichwort „$kw” nicht erwartet" >&2
            ok=0
        fi
    done
    [ "$ok" -eq 1 ] || fail=1
}

# --- guter Fall: keine Befunde, keine Hinweise
run_script "$HERE/fixtures/gut"
expect 0 "Keine Befunde."
expect_not 0 "Hinweis"

# --- schlechter Fall: Befunde bei Symfony-Projekt
run_script "$HERE/fixtures/schlecht"
expect 1 "cookie_secure" "csrf_protection" "enable_csrf: false" "ohne File-Constraint" "schließt .git nicht aus"
expect 1 "OhneCsrfType.php:7: Formular schaltet csrf_protection ab"

# --- Hinweise ändern den Exit nie (kein config/ => kein Symfony => keine Befunde)
run_script "$HERE/fixtures/hinweise"
expect 0 "SQL mit eingesetzter Variable" "|raw" "md5" "shell_exec" "prefers-reduced-motion" "strict" "fokus.css:1: outline:none ohne :focus-visible"
expect 0 "Code.php:2: mt_rand für Sicherheitszwecke"
expect 0 "MehrzeiligRepo.php:7: SQL mit eingesetzter Variable"
expect_not 0 "exec("
expect_not 0 "UserRepo.php:3: "

# --- kein Projekt: nicht messbar
run_script "$HERE/fixtures/leer"
expect 77 "nicht messbar"

# --- Nutzungsfehler: zwei Argumente
run_script "$HERE/fixtures/gut" "$HERE/fixtures/gut"
expect 2

# --- Nutzungsfehler: Verzeichnis existiert nicht
run_script "$HERE/fixtures/dies-existiert-nicht"
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
