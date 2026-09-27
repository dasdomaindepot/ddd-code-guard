#!/usr/bin/env bash
#
# Selbsttest für check-secrets.
#
# Fährt das Script für jeden Fall (ein Verzeichnis als Argument) und prüft
# Exit-Code und Ausgabe. Die Fälle werden zur Laufzeit in einem mktemp-Verzeichnis
# aufgebaut; der Check braucht ein Git-Repo (`git init -q`, `git add -A`). Am
# Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-secrets"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

# gitleaks: lokal im PATH oder als lokales Docker-Image? Nur dann ist S3 messbar.
gitleaks_verfügbar() {
    command -v gitleaks >/dev/null 2>&1 && return 0
    docker image inspect zricethezav/gitleaks:latest >/dev/null 2>&1 && return 0
    return 1
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

new_project() {
    # Leeres Git-Repo zurückgeben; räumt beim Aufrufer per trap auf.
    mktemp -d
}

random_token() {
    echo "ghp_$(head -c 64 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 36)"
}

random_hex() {
    head -c 64 /dev/urandom | base64 | tr -dc 0-9a-f | head -c 32
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# --- guter Fall: keine Geheimnisse, S3 ggf. nur Hinweis ---------------
GUT="$(new_project)"
(
    cd "$GUT"
    git init -q
    printf '{}\n' > composer.json
    printf 'APP_SECRET=\n' > .env
    printf '<?php\n$x = 1;\n' > src.php
    git add -A
)
run_script "$GUT"
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"
rm -rf "$GUT"

# --- S1: versionierte lokale .env-Dateie --------------------------------
ENV_LOCAL="$(new_project)"
(
    cd "$ENV_LOCAL"
    git init -q
    printf 'X=1\n' > .env.local
    git add -A
)
run_script "$ENV_LOCAL"
expect 1 ".env.local ist versioniert"
expect 1 "Befund(e)."
rm -rf "$ENV_LOCAL"

# --- S2: echter APP_SECRET in .env, Wert darf nicht ausgegeben werden ---
APP_SECRET_DIR="$(new_project)"
SECRET="$(random_hex)"
(
    cd "$APP_SECRET_DIR"
    git init -q
    printf 'APP_SECRET=%s\n' "$SECRET" > .env
    git add -A
)
run_script "$APP_SECRET_DIR"
expect 0 "APP_SECRET steht mit echtem Wert"
# Exit 0, da S2 ein Hinweis ist; Wert darf nicht in der Ausgabe stehen.
expect_not 0 "$SECRET"
rm -rf "$APP_SECRET_DIR"

# --- S3: gitleaks-Treffer (nur wenn messbar) ----------------------------
if gitleaks_verfügbar; then
    LEAK="$(new_project)"
    TOKEN="$(random_token)"
    (
        cd "$LEAK"
        git init -q
        mkdir -p src
        printf '<?php\n$t = "%s";\n' "$TOKEN" > src/a.php
        git add -A
    )
    run_script "$LEAK"
    expect 1 "gitleaks github-pat"
    expect 1 "Befund(e)."
    expect_not 1 "$TOKEN"
    # bewusste Ausnahme per .gitleaksignore → wieder exit 0
    printf 'src/a.php:github-pat:2\n' > "$LEAK/.gitleaksignore"
    run_script "$LEAK"
    expect 0 "Keine Befunde."
    rm -rf "$LEAK"
else
    echo "ÜBERSPRUNGEN: gitleaks nicht verfügbar — S3-Fall nicht messbar" >&2
fi

# --- kein Git-Repo: nicht messbar ---------------------------------------
NOGIT="$(new_project)"
run_script "$NOGIT"
expect 77
rm -rf "$NOGIT"

# --- Nutzungsfehler: zwei Argumente -------------------------------------
GUT2="$(new_project)"
(
    cd "$GUT2"
    git init -q
    printf '{}\n' > composer.json
    git add -A
)
run_script "$GUT2" "$GUT2"
expect 2
rm -rf "$GUT2"

# --- Nutzungsfehler: Verzeichnis existiert nicht ------------------------
run_script "$TMPROOT/dies-existiert-nicht"
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
