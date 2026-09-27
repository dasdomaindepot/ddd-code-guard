#!/usr/bin/env bash
#
# Selbsttest für check-auth-policy.
#
# Fährt das Script für jeden Fixture-Ordner direkt (ein Verzeichnis als
# Argument; es wird nichts gestartet oder aufgerufen) und prüft Exit-Code
# und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-auth-policy"

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

# --- guter Fall: keine Befunde, Sperre nach 5 Fehlversuchen, NIST NICHT ---
run_script "$HERE/fixtures/gut"
expect 0 "Keine Befunde." "Fehlversuchen (login_throttling)" "Abgleich mit geleakten"
expect_not 0 "NIST"

# --- OIDC/SSO: kein lokaler Passwort-Login, Brute Force Detection hint ---
run_script "$HERE/fixtures/oidc"
expect 0 "Brute Force Detection" "keine Passwortvergabe gefunden"

# --- eigener RateLimiter im Custom-Authenticator
run_script "$HERE/fixtures/custom-limiter"
expect 0 "eigene Sperre per RateLimiter"

# --- Passwort-Minsteänge 12, NIST-Hinweis, kein NotCompromisedPassword
run_script "$HERE/fixtures/zwoelf"
expect 0 "Keine Befunde." "12 Zeichen" "NIST SP 800-63B-4" "NotCompromisedPassword einbauen"

# --- Projekt-Policy: guard-policy.yml im Projekt (min 10), keine Befunde
run_script "$HERE/fixtures/projekt-policy"
expect 0 "Keine Befunde."

# --- zu viele Fehlversuche (50 > 10)
run_script "$HERE/fixtures/zu-viele-versuche"
expect 1 "login_throttling erlaubt 50 Fehlversuche"

# --- ohne temporäre Sperre, aber Passwortvergabe
run_script "$HERE/fixtures/ohne-sperre"
expect 1 "ohne temporäre Sperre" "keine Passwortvergabe gefunden"

# --- zu kurzes Passwort mit Mindest- und Höchstlänge
run_script "$HERE/fixtures/kurzes-passwort"
expect 1 "Mindestlänge 8" "Höchstlänge 32" "geleakten"

# --- keine Mindestlänge bei vergebenen Passwörtern
run_script "$HERE/fixtures/keine-laenge"
expect 1 "keine Mindestlänge gefunden"

# --- Symfony-Tags (!php/const) müssen nicht abstürzen
run_script "$HERE/fixtures/symfony-tags"
expect 1 "ohne temporäre Sperre"

# --- schwache Passwort-Hasher (md5, sha512) — Befunde; when@test-Hasher oberster Ebene wird ignoriert
run_script "$HERE/fixtures/schwacher-hasher"
expect 1 "App\Entity\User nutzt md5" "App\Entity\Admin nutzt sha512" "ASVS 11.4.2"

# --- InMemoryUser plaintext ohne memory-Provider mit Benutzern — nur Hinweis
run_script "$HERE/fixtures/inmemory-plaintext"
expect 0 "keinen memory-Provider"

# --- kein security.yaml: nicht messbar
run_script "$HERE/fixtures/no-security-yaml"
expect 77 "nicht messbar"

# --- Passwort ändern ohne altes Passwort; das Reset-Formular zählt nicht
run_script "$HERE/fixtures/ohne-altes-passwort"
expect 0 "src/Form/ChangePasswordType.php: Passwort ändern ohne Abfrage"
expect_not 0 "ChangePasswordFormType.php"

# --- strlen: handgeschriebene Mindestlänge wird erkannt
run_script "$HERE/fixtures/strlen"
expect 1 "Mindestlänge 8" "PasswordResetApiController.php:12"
expect_not 1 "keine Mindestlänge gefunden"

# --- ohne Argument: aktuelles Verzeichnis (hier ohne security.yaml)
OUT="$(cd "$HERE/fixtures/no-security-yaml" && "$SCRIPT" 2>&1)" && RC=0 || RC=$?
expect 77

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
