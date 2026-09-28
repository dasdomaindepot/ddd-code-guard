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

# --- S8: Docker-Hardening — feste Version fehlt, Secret in ENV, prod-Stufe
#     ohne USER. Der feste ARG ohne Wert liefert keinen Befund.
run_script "$HERE/fixtures/docker-hart"
expect 1 "ohne feste Version" "API_TOKEN" "Container läuft als root"
expect_not 1 "abc123geheim"
expect_not 1 "DB_PASSWORD"

# --- S9: nginx-offen — server_tokens fehlt, general PHP location ohne
#     Schutz von public/uploads, Uploads aber ohne client_max_body_size.
run_script "$HERE/fixtures/nginx-offen"
expect 1 "server_tokens off" "public/uploads: PHP-Dateien" "client_max_body_size"

# --- S9: nginx-gut — Front-Controller, server_tokens off, client_max_body_size
#     gesetzt: kein S9-Befund, kein S9-Hinweis.
run_script "$HERE/fixtures/nginx-gut"
expect 0 "Keine Befunde."
expect_not 0 "verrät seine Version" "PHP-Dateien darin" "client_max_body_size passend"

# --- Geldbetrag als float: genau ein Befund (totalPrice), netto und taxRate nicht
run_script "$HERE/fixtures/geld-float"
expect 1 "Geldbetrag totalPrice als float"
expect_not 1 "netto als float"
expect_not 1 "taxRate als float"
expect_not 1 "Geldbetrag netto"
expect_not 1 "Geldbetrag taxRate"

# --- S7: öffentlich cachebare Antwort in geschütztem Controller. Genau ein
# Befund zu KontoController.php (setSharedMaxAge); StartController ohne Schutz
# wird nicht gemeldet.
run_script "$HERE/fixtures/cache-public"
expect 1 "KontoController.php" "Reverse-Proxy liefert sie an andere Nutzer aus"
expect_not 1 "StartController.php"
befunde=$(printf '%s' "$OUT" | grep -cF "BEFUND   " || true)
if [ "$befunde" -ne 1 ]; then
    echo "FEHLER: erwartet genau 1 Befund, aber $befunde" >&2
    printf '%s\n' "$OUT" >&2
    fail=1
fi

# --- S10: Platzhalter in Übersetzungsdateien. en hat %nom% statt %name% in
#     gruss (ein Befund); anzahl (ICU-Plural, # ignoriert, Wort im Zweig kein
#     Platzhalter) und ok stimmen überein und werden nicht gemeldet.
run_script "$HERE/fixtures/translations"
expect 1 "gruss hat %nom% statt %name%" "(Referenz de)"
expect_not 1 "anzahl"
expect_not 1 "messages.en.yaml: ok"
expect_not 1 "Eintrag"
expect_not 1 "entries"
befunde=$(printf '%s' "$OUT" | grep -cF "BEFUND   " || true)
if [ "$befunde" -ne 1 ]; then
    echo "FEHLER: erwartet genau 1 Befund, aber $befunde" >&2
    printf '%s\n' "$OUT" >&2
    fail=1
fi

# --- Hinweise ändern den Exit nie (kein config/ => kein Symfony => keine Befunde)
run_script "$HERE/fixtures/hinweise"
expect 0 "SQL mit eingesetzter Variable" "|raw" "md5" "shell_exec" "prefers-reduced-motion" "strict" "fokus.css:1: outline:none ohne :focus-visible"
expect 0 "Code.php:2: mt_rand für Sicherheitszwecke"
expect 0 "MehrzeiligRepo.php:7: SQL mit eingesetzter Variable"
expect 0 "HTTP-Client ohne timeout"
expect 0 "ohne Timeout und Fehlerbehandlung"
expect_not 0 "exec("
expect_not 0 "UserRepo.php:3: "

# --- H6: "strict" unter compilerOptions (dort gehört es hin) → kein Hinweis
run_script "$HERE/fixtures/tsconfig-strict"
expect 0
expect_not 0 "strict"

# --- H8: PHP-Sicherheits-Patzer in src-PHP (@-Unterdrückung, json_decode,
# Request-Typcast). Die drei Beispiele melden sich an; @var und @ in Strings
# (z. B. 'a@b.de') werden nicht als Fehlerunterdrückung gemeldet.
run_script "$HERE/fixtures/hinweise"
expect 0 "@-Fehlerunterdrückung versteckt Fehler"
expect 0 "json_decode ohne JSON_THROW_ON_ERROR"
expect 0 "validieren statt casten"
at_hint=$(printf '%s' "$OUT" | grep -cF "@-Fehlerunterdrückung versteckt Fehler" || true)
if [ "$at_hint" -ne 1 ]; then
    echo "FEHLER: erwartet genau 1 @-Hinweis, aber $at_hint (z. B. @var oder @ in String)" >&2
    printf '%s\n' "$OUT" >&2
    fail=1
fi

# --- symfony/http-client ohne Timeout in default_options (Hinweis, Exit 0)
run_script "$HERE/fixtures/http-client"
expect 0 "default_options ohne timeout"

# --- S5: gefährliche Produktions-Konfiguration (Fixture war angelegt, aber nie geprüft)
run_script "$HERE/fixtures/prod-debug"
expect 1 "[app-static/S5]" "Session Fixation" "Profiler/Debug in Produktion" "FooDevBundle kommt aus require-dev" "Debug-Modus"

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
