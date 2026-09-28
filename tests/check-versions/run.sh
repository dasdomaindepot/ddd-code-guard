#!/usr/bin/env bash
#
# Selbsttest für check-versions.
#
# Fährt das Script für jeden Fixture-Ordner direkt (ein Verzeichnis als
# Argument) mit fixen Supportdaten aus GUARD_EOL_DIR, festem Tag GUARD_TODAY
# und einer outdated-Datei aus GUARD_OUTDATED_JSON — ohne jeglichen Netz- oder
# Containerzugriff. Prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-versions"

# Kein Netz im Test: Supportdaten nur aus den Fixtures, festes "Heute",
# composer outdated nur aus der Datei.
export GUARD_EOL_DIR="$HERE/fixtures/eol"
export GUARD_TODAY="2026-09-28"
export GUARD_OUTDATED_JSON="$HERE/fixtures/outdated.json"

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

# --- alt: abgelaufener PHP-Support (Befund), Symfony bald EOL (Hinweis),
# --- veraltete Hauptversion (Heweis) — Exit 1 wegen des Befunds
run_script "$HERE/fixtures/alt"
expect 1 "1 Befund(e)."
expect 1 "BEFUND" "PHP 8.1 bekommt seit 2025-12-31" "auf eine unterstützte Version heben"
expect 1 "Symfony 7.2 verliert am 2026-11-30 den Support"
expect 1 "Hinweis  symfony/framework-bundle 6.4.34 → 7.3.4 (neue Hauptversion)"

# --- aktuell: PHP und Symfony unterstützt — Exit 0, kein Befund
run_script "$HERE/fixtures/aktuell"
expect 0 "Keine Befunde."
expect 0 "ok       PHP 8.3: unterstützt bis 2027-12-31"
expect 0 "Symfony 7.3 verliert am 2027-01-31 den Support"
expect_not 0 "BEFUND" "bekommt seit"

# --- GUARD_EOL_DIR auf ein leues Verzeichnis → keine Supportdaten → 77
empty_eol="$(mktemp -d)"
GUARD_EOL_DIR="$empty_eol" run_script "$HERE/fixtures/alt"
expect 77
rm -rf "$empty_eol"

# --- kein composer.json → nicht messbar
run_script "$HERE/fixtures/kein-projekt"
expect 77

# --- Nutzungsfehler: zwei Argumente
run_script "$HERE/fixtures/alt" "$HERE/fixtures/aktuell"
expect 2

# --- Nutzungsfehler: Verzeichnis existiert nicht
run_script "$HERE/fixtures/dies-existiert-nicht"
expect 2

# --- Der Script darf im Test kein Netz machen: HOME auf ein leeres Verzeichnis
# --- setzen und prüfen, dass kein code-guard-Cache angelegt wurde.
tmp_home="$(mktemp -d)"
HOME="$tmp_home" run_script "$HERE/fixtures/aktuell"
if [ -d "$tmp_home/.cache/code-guard" ]; then
    echo "FEHLER: $tmp_home/.cache/code-guard wurde trotz GUARD_EOL_DIR angelegt" >&2
    fail=1
fi
rm -rf "$tmp_home"

# --- echter Aufrufweg: composer outdated über ein vorgetäuschtes docker
# (ohne GUARD_OUTDATED_JSON). Deckt ab, dass die JSON-Ausgabe als Text
# geparst wird – früher wurde sie fälschlich als Dateipfad gelesen.
fake_bin="$(mktemp -d)"
cat > "$fake_bin/docker" <<'SH'
#!/bin/sh
case "$*" in
  *"ps --services"*) echo php ;;
  *"composer outdated"*) echo '{"installed":[{"name":"acme/paket","version":"1.2.0","latest":"2.0.0"}]}' ;;
esac
SH
chmod +x "$fake_bin/docker"
OUT="$(env -u GUARD_OUTDATED_JSON PATH="$fake_bin:$PATH" "$SCRIPT" "$HERE/fixtures/aktuell" 2>&1)" && RC=0 || RC=$?
expect 0 "acme/paket 1.2.0 → 2.0.0"
rm -rf "$fake_bin"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
