#!/usr/bin/env bash
#
# Selbsttest für check-house-rules.
#
# Fährt das Script für jeden Fixture-Ordner direkt (ein Verzeichnis als
# Argument; es wird nichts gestartet oder aufgerufen) und prüft Exit-Code
# und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-house-rules"

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

# --- guter Fall: phpcs 4, gültiges Regelwerk, keine Befunde
run_script "$HERE/fixtures/gut"
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- schlechter Fall: phpcs 4, mehrere Befunde (relativ, Komma-Array, Slevomat)
run_script "$HERE/fixtures/schlecht"
expect 1 "4 Befund(e)." 'type="relative"' "forbiddenFunctions" "slevomat/coding-standard" "phpcs.xml:5:"

# --- phpcs 3: Regel R1 entfällt,egal was das Regelwerk kann
run_script "$HERE/fixtures/phpcs3"
expect 0 "Regel R1 entfällt"

# --- kein Lock: phpcs nicht installiert, R1 entfällt
run_script "$HERE/fixtures/ohne-lock"
expect 0 "Regel R1 entfällt"

# --- kein Projekt: nicht messbar
run_script "$HERE/fixtures/leer"
expect 77

# --- Nutzungsfehler: zwei Argumente
run_script "$HERE/fixtures/gut" "$HERE/fixtures/gut"
expect 2

# --- Nutzungsfehler: Verzeichnis existiert nicht
run_script "$HERE/fixtures/dies-existiert-nicht"
expect 2

# --- R2: ungeschütztes $ in .env-Wert verstümmelt Docker-Compose die Interpolation
run_script "$HERE/fixtures/env-dollar"
expect 1 "1 Befund(e)." '.env:7: DB_PASSWORD'
expect_not 1 'abc' 'XYZdef' 'DB_PASSWORD=abc'

# --- R3: Zeitzone durchgehend Europe/Berlin — ini mit korrektem Wert
run_script "$HERE/fixtures/tz-gut"
expect 0 "Container und PHP in Europe/Berlin"

# --- R3: date.timezone per echo im Dockerfile via $TZ gesetzt
run_script "$HERE/fixtures/tz-dockerfile-echo"
expect 0 "Container und PHP in Europe/Berlin"

# --- R3: keine ini mit date.timezone (Kommentar zählt nicht)
run_script "$HERE/fixtures/tz-ohne-ini"
expect 1 "keine date.timezone"

# --- R3: Container und PHP auf UTC
run_script "$HERE/fixtures/tz-utc"
expect 1 "2 Befund(e)." "Hausstandard ist Europe/Berlin"

# --- R3: kein PHP-Dockerfile vorhanden
run_script "$HERE/fixtures/tz-kein-php"
expect 0 "Regel R3 entfällt"

# --- R4: trusted_proxies hinter Traefik + nginx — Standard ist %env(TRUSTED_PROXIES)%
run_script "$HERE/fixtures/tp-gut"
expect 0 "trusted_proxies: %env(TRUSTED_PROXIES)%"

# --- R4: leerer Default in %env(default::…)% bricht mit ungültigem Typ ab
run_script "$HERE/fixtures/tp-default-leer"
expect 1 "default::"

# --- R4: feste CIDR hinter nginx mit real_ip_header greift nie, plus trusted_headers
run_script "$HERE/fixtures/tp-private-ranges"
expect 1 "2 Befund(e)." "greift hinter nginx" "Host-Header-Injection"

# --- R4: trusted_proxies fehlt, obwohl nginx real_ip_header setzt
run_script "$HERE/fixtures/tp-fehlt"
expect 1 "trusted_proxies fehlt"

# --- R4: framework.yaml ohne trusted_proxies und kein docker/ — Regel R4 passt
run_script "$HERE/fixtures/tp-managed"
expect 0 "R4 passt"

# --- R5: Deploy mit needs ["build"] wartet nicht auf Prüf-Jobs
run_script "$HERE/fixtures/ci-needs-build"
expect 1 "2 Befund(e)." 'Job "deploy" hat needs' 'Job "deploy_stage" hat needs'

# --- R5: Deploy braucht alle Prüf-Jobs in needs — gut
run_script "$HERE/fixtures/ci-needs-gut"
expect 0 "Deploy wartet auf die Prüf-Jobs"
expect_not 0 "BEFUND"

# --- R5: Deploy ohne needs wartet über Stage, aber Prüf-Job allow_failure
run_script "$HERE/fixtures/ci-stages"
expect 0 "allow_failure"
expect_not 0 "BEFUND"

# --- R5: keine Prüf-Jobs — Regel R5 entfällt
run_script "$HERE/fixtures/ci-ohne-tests"
expect 0 "keine Prüf-Jobs"

# --- R5: Folge-Job nach dem Deploy (e2e) wird nicht doppelt gemeldet
run_script "$HERE/fixtures/ci-folge-deploy"
expect 1 "1 Befund(e)." 'Job "deploy" hat needs'
expect_not 1 'Job "e2e"'

# --- R6: Plattform passt zum PHP im Dockerfile (Container 8.3)
run_script "$HERE/fixtures/platform-gut"
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- R6: config.platform.php (8.2) weicht von PHP 8.3 im Dockerfile ab
run_script "$HERE/fixtures/platform-falsch"
expect 1 "passt nicht zur PHP-Version"

# --- R6: composer.lock ist da, aber nicht versioniert
tmp_platform_git="$(mktemp -d)"
git -C "$tmp_platform_git" init -q
printf '{\n  "require": {"php": "^8.3"}\n}\n' > "$tmp_platform_git/composer.json"
printf '{}\n' > "$tmp_platform_git/composer.lock"
git -C "$tmp_platform_git" add composer.json
run_script "$tmp_platform_git"
expect 1 "composer.lock ist nicht versioniert"
rm -rf "$tmp_platform_git"

# --- R6: composer.lock ist versioniert, kein R6-Befund
tmp_platform_git_ok="$(mktemp -d)"
git -C "$tmp_platform_git_ok" init -q
printf '{\n  "require": {}\n}\n' > "$tmp_platform_git_ok/composer.json"
printf '{}\n' > "$tmp_platform_git_ok/composer.lock"
git -C "$tmp_platform_git_ok" add composer.json composer.lock
run_script "$tmp_platform_git_ok"
expect 0
expect_not 0 "nicht versioniert"
rm -rf "$tmp_platform_git_ok"

# --- R7: messenger ohne failure_transport (Befund), async ohne retry
# --- (Hinweis) und Worker ohne Limit (Hinweis) — Exit 1 wegen des Befunds
run_script "$HERE/fixtures/messenger-ohne-failure"
expect 1 "1 Befund(e)." "failure_transport" "retry_strategy" "--memory-limit"

# --- R7: messenger in Ordnung — kein Befund, kein Hinweis
run_script "$HERE/fixtures/messenger-gut"
expect 0 "Keine Befunde."
expect_not 0 "BEFUND" "Hint"

# --- R8: Cron — Zeile 1 ohne Lock (Hinweis), Zeile 2 mit LockableTrait (kein
# --- Hinweis), Zeile 3 über flock (kein Hinweis) — Exit 0, genau ein Hinweis
run_script "$HERE/fixtures/cron"
expect 0 "Keine Befunde."
expect 0 "crontab:1: app:ohne-lock läuft ohne Lock"
expect_not 0 'crontab:2:' 'crontab:3:'

# --- R8: keine Crontab — Regel R8 entfällt
run_script "$HERE/fixtures/gut"
expect 0 "Regel R8 entfällt"

# --- R9: DATABASE_URL verbindet als root — root in Produktion Befund,
# --- in .env/.env.local nur Hinweis; Passwort und URL werden nie ausgegeben
run_script "$HERE/fixtures/db-root"
expect 1 "1 Befund(e)." "BEFUND" ".env.prod:1:" ".env:1:"
expect 1 "Hinweis  [house-rules/R9] .env:1: DATABASE_URL verbindet als root"
expect_not 1 "geheim123" "prodgeheim"

# --- R10: healthcheck und Volumes in docker-compose — nur Hinweise
# --- php und nginx ohne healthcheck, public/uploads nur über Code-Mount
run_script "$HERE/fixtures/compose"
expect 0 "Keine Befunde."
expect 0 "Hinweis  [house-rules/R10] Dienst php ohne healthcheck"
expect 0 "Hinweis  [house-rules/R10] Dienst nginx ohne healthcheck"
expect 0 "Hinweis  [house-rules/R10] public/uploads liegt nur"
expect 0 "in Produktion prüfen"
expect_not 0 "BEFUND"

# --- R10: kein Compose — Regel R10 entfällt
run_script "$HERE/fixtures/gut"
expect 0 "Regel R10 entfällt"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
