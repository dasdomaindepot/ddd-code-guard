#!/usr/bin/env bash
#
# Selbsttest für check-symfony-lint.
#
# Fährt das Script gegen ein zur Laufzeit angelegtes Fixture-Projekt. Der
# php-Container wird durch ein Fake-docker ersetzt (über die Umgebungsvariable
# GUARD_DOCKER), das anhand der Argumente antwortet. Das Verhalten der
# Symfony-Befehle wird über FAKE_CASE gesteuert; die Aufrufe werden in eine
# Log-Datei geschrieben, damit der Test etwa prüfen kann, ob ein schreibender
# Befehl aufgerufen wurde.
#
# Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-symfony-lint"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

RC=0
OUT=""
fail=0

# Fake-docker und Fixture-Verzeichnis pro Fall.
WORK=""
FAKE_LOG=""
LAST_FIXTURE=""

cleanup() {
    if [ -n "$WORK" ]; then
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

make_fake_docker() {
    WORK="$(mktemp -d)"
    FAKE_LOG="$WORK/invocations.log"

    cat > "$WORK/docker" <<'FAKE'
#!/usr/bin/env bash
# Fake docker für check-symfony-lint: protokalliert jeden Aufruf nach
# $FAKE_LOG und antwortet je nach $FAKE_CASE.
log() { printf 'docker %s\n' "$*" >> "$FAKE_LOG"; }
log "$*"

# Container-am-check: FAKE docker ersetzt "docker", bekommt also die Argumente
# ohne führenden Namen: compose exec -T php true
if [ "$1" = compose ] && [ "$2" = exec ] && [ "$3" = -T ] && \
   [ "$4" = php ] && [ "$5" = true ]; then
    exit "${FAKE_TRUE_RC:-0}"
fi

# Befehle nach --no-interaction sammeln
args=()
after=0
for a in "$@"; do
    if [ "$a" = --no-interaction ]; then after=1; continue; fi
    if [ "$after" -eq 1 ]; then
        args+=("$a")
    fi
done

cmd="${args[0]:-}"
json='{"commands":[{"name":"lint:container"},{"name":"lint:twig"},{"name":"lint:yaml"},{"name":"doctrine:schema:validate"},{"name":"doctrine:migrations:up-to-date"}]}'

case "$cmd" in
    list)
        printf '%s\n' "$json"
        # Wie Monolog im Dev-Modus: Deprecations als JSON-Zeile auf stderr
        if [ "${FAKE_CASE:-all-green}" = deprecation-stderr ]; then
            printf '%s\n' '{"message":"User Deprecated: Since symfony/x 7.4: foo","channel":"deprecation","level":200}' >&2
        fi
        exit 0
        ;;
    lint:container)
        exit 0
        ;;
    lint:twig)
        exit 0
        ;;
    lint:yaml)
        if [ "${FAKE_CASE:-all-green}" = lint-yaml-fail ]; then
            printf 'In "config/packages/security.yaml" Zeile 12:\n  Unrecognized tag !tagged_iterator.\n'
            exit 1
        fi
        exit 0
        ;;
    doctrine:schema:validate)
        flag="${args[1]:-}"
        if [ "$flag" = "--skip-mapping" ]; then
            if [ "${FAKE_CASE:-all-green}" = schema-diverges ]; then
                printf 'Mapping:\n  ! ERROR!\n    - App\\Entity\\User weicht von der Datenbank ab.\n'
                exit 1
            fi
            exit 0
        fi
        # --skip-sync (Hauptprüfung)
        exit 0
        ;;
    doctrine:migrations:up-to-date)
        if [ "${FAKE_CASE:-all-green}" = migrations-open ]; then
            printf 'Es liegen 2 migrations ausstehend vor.\n'
            exit 1
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
FAKE
    chmod +x "$WORK/docker"
}

make_fixture() {
    local dir="$1"
    mkdir -p "$dir/bin" "$dir/templates" "$dir/config/packages"
    : > "$dir/bin/console"
    cat > "$dir/docker-compose.yml" <<'YML'
services:
  php:
    image: php:cli
YML
}

reset_env() {
    export GUARD_DOCKER="$WORK/docker"
    export FAKE_CASE="${1:-all-green}"
    export FAKE_LOG
    unset FAKE_TRUE_RC
    : > "$FAKE_LOG"
}

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

expect_log_not() {
    local kw="$1"
    if [ -f "$FAKE_LOG" ] && grep -qF -- "$kw" "$FAKE_LOG"; then
        echo "FEHLER: $kw wurde im Fake-docker-Log gefunden (nicht aufgerufen)" >&2
        fail=1
    fi
}

expect_log() {
    local kw="$1"
    if [ -f "$FAKE_LOG" ] && grep -qF -- "$kw" "$FAKE_LOG"; then
        :
    else
        echo "FEHLER: $kw wurde im Fake-docker-Log nicht gefunden" >&2
        fail=1
    fi
}

# --- Setup einmalig ---
make_fake_docker

# --- alles grün → Exit 0, "Keine Befunde." ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env all-green
run_script "$LAST_FIXTURE"
expect 0 "Keine Befunde."
expect_not 0 "BEFUND" "Hinweis"

# --- lint:yaml scheitert → Exit 1, "lint:yaml" ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env lint-yaml-fail
run_script "$LAST_FIXTURE"
expect 1 "1 Befund(e)." "lint:yaml"
expect_not 1 "Keine Befunde."

# --- Migrationen offen → Exit 0, "lokal nicht ausgeführt"; --skip-mapping NICHT aufgerufen ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env migrations-open
run_script "$LAST_FIXTURE"
expect 0 "lokal nicht ausgeführt"
expect 0 "Hinweis"
expect_not 0 "BEFUND"
expect_log_not "--skip-mapping"

# --- Migrationen aktuell, Schema weicht ab → Exit 1, "Entity geändert ohne Migration" ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env schema-diverges
run_script "$LAST_FIXTURE"
expect 1 "Entity geändert ohne Migration"
expect_log "--skip-mapping"

# --- exec -T php true scheitert → Exit 77 ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env all-green
export FAKE_TRUE_RC=1
run_script "$LAST_FIXTURE"
expect 77 "nicht messbar"

# --- kein bin/console → Exit 77 ---
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
mkdir -p "$LAST_FIXTURE"
echo "x" > "$LAST_FIXTURE/docker-compose.yml"
reset_env all-green
run_script "$LAST_FIXTURE"
expect 77 "nicht messbar"

# --- zwei Argumente → Exit 2 ---
run_script "$LAST_FIXTURE" "$LAST_FIXTURE"
expect 2

# --- #1990: Deprecation-Zeile auf stderr darf list --format=json nicht zerstören
LAST_FIXTURE="$(mktemp -d "$WORK/fixture.XXXXXX")"
make_fixture "$LAST_FIXTURE"
reset_env deprecation-stderr
run_script "$LAST_FIXTURE"
expect 0 "Keine Befunde."
expect_not 0 "bootet nicht"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
