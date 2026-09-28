#!/usr/bin/env bash
#
# Tests für guard-profile-draft.
#
#   bash tests/guard-profile-draft/run.sh
#
# Prüft den Entwurf gegen zwei Fixtures (voll, leer), die YAML-Validität, die
# Vermeidung falscher Kurzformen und dass im Fixture-Verzeichnis nichts
# angelegt wird. Gibt „OK: alle Fälle bestanden“ aus, wenn nichts fehlschlägt.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../claude/skills/code-quality/bin/guard-profile-draft"
FIXTURES="$HERE/fixtures"

pass=0
fail=0

ok() { echo "OK:   $1"; pass=$((pass + 1)); }
bad() { echo "FEHLER: $1"; fail=$((fail + 1)); }

contains() { # "text" "nadel" "Label"
    if printf '%s' "$1" | grep -qF -- "$2"; then
        ok "$3"
    else
        bad "$3 — erwartet nicht gefunden: [$2]"
    fi
}

not_contains() { # "text" "nadel" "Label"
    if printf '%s' "$1" | grep -qF -- "$2"; then
        bad "$3 — unerwartet gefunden: [$2]"
    else
        ok "$3"
    fi
}

# --- voll -----------------------------------------------------------------

set +e
FULL="$(python3 "$SCRIPT" "$FIXTURES/voll")"
FULL_RC=$?

[ "$FULL_RC" -eq 0 ] && ok "voll: Exit 0" || bad "voll: Exit $FULL_RC (erwartet 0)"

contains "$FULL" "version: 1" "voll: version: 1"
contains "$FULL" "datenbank: mariadb" "voll: datenbank: mariadb (serverVersion MariaDB)"
contains "$FULL" "auth: [formular]" "voll: auth: [formular]"
contains "$FULL" "messenger: [async]" "voll: messenger: [async]"
contains "$FULL" "mandanten: spalte" "voll: mandanten: spalte"
contains "$FULL" "mandanten_feld: organisation" "voll: mandanten_feld: organisation"
contains "$FULL" "geldbetraege: ja" "voll: geldbetraege: ja"
contains "$FULL" "deployment: symfony-docker" "voll: deployment: symfony-docker"

MES_LINE="$(printf '%s' "$FULL" | grep '^messenger:')"
not_contains "$MES_LINE" "failed" "voll: messenger-Zeile enthält kein failed"

if printf '%s' "$FULL" | python3 -c 'import sys, yaml; yaml.safe_load(sys.stdin)' >/dev/null 2>&1; then
    ok "voll: Ausgabe YAML-parsebar"
else
    bad "voll: Ausgabe nicht YAML-parsebar"
fi

# --- leer -----------------------------------------------------------------

set +e
LEER="$(python3 "$SCRIPT" "$FIXTURES/leer")"
LEER_RC=$?

[ "$LEER_RC" -eq 0 ] && ok "leer: Exit 0" || bad "leer: Exit $LEER_RC (erwartet 0)"

contains "$LEER" "version: 1" "leer: version: 1"
contains "$LEER" "unbekannt" "leer: kennzeichnet Werte als unbekannt"
not_contains "$LEER" "geldbetraege: nein" "leer: kein geldbetraege: nein"
not_contains "$LEER" "mandanten: keine" "leer: kein mandanten: keine"

if printf '%s' "$LEER" | python3 -c 'import sys, yaml; yaml.safe_load(sys.stdin)' >/dev/null 2>&1; then
    ok "leer: Ausgabe YAML-parsebar"
else
    bad "leer: Ausgabe nicht YAML-parsebar"
fi

# --- Nutzungsfehler -------------------------------------------------------

python3 "$SCRIPT" eine zwei >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "zwei Argumente: Exit 2" || bad "zwei Argumente: Exit $RC (erwartet 2)"

python3 "$SCRIPT" "$FIXTURES/niicht" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "fehlendes Verzeichnis: Exit 2" || bad "fehlendes Verzeichnis: Exit $RC (erwartet 2)"

# --- keine Nebenwirkung im Fixture-Verzeichnis ----------------------------

BEFORE="$(cd "$FIXTURES" && find . | sort)"
python3 "$SCRIPT" "$FIXTURES/voll" >/dev/null 2>&1
python3 "$SCRIPT" "$FIXTURES/leer" >/dev/null 2>&1
AFTER="$(cd "$FIXTURES" && find . | sort)"

if [ "$BEFORE" = "$AFTER" ]; then
    ok "keine Datei in fixtures/ angelegt"
else
    bad "fixtures/ wurde verändert:"
    diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | sed 's/^/        /'
fi

# --- Fazit ----------------------------------------------------------------

echo
# --- include mit project + file-Liste, DATABASE_URL leer in .env und gesetzt in .env.local
INC="$(python3 "$SCRIPT" "$FIXTURES/include-liste")"
contains "$INC" "deployment: symfony-docker" "include-liste: deployment aus file-Liste"
contains "$INC" "datenbank: postgresql" "include-liste: .env.local überschreibt leeres DATABASE_URL"
contains "$INC" "oeffentliche_api:" "include-liste: Schlüssel oeffentliche_api"
not_contains "$INC" "öffentliche_api" "include-liste: kein Umlaut im Schlüssel"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi

echo "$fail Fehler, $pass Fälle bestanden"
exit 1
