#!/usr/bin/env bash
#
# Selbsttest für check-gate-integrity.
#
# Da ein Git-Verlauf nötig ist, wird jeder Fall zur Laufzeit in einem
# mktemp-Verzeichnis aufgebaut: Basis-Commit auf `main`, Branch `feature`,
# danach die Änderung im Arbeitsbaum bzw. zweiter Commit. Das Script wird
# mit <projektverzeichnis> <basis-ref=main> aufgerufen und prüft Exit-Code
# und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-gate-integrity"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

RC=0
OUT=""
fail=0

TMPDIRS=()
cleanup() {
    for d in "${TMPDIRS[@]:-}"; do
        [ -n "$d" ] && rm -rf "$d"
    done
}
trap cleanup EXIT

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

new_repo() {
    local d
    d="$(mktemp -d)"
    TMPDIRS+=("$d")
    git -C "$d" init -q -b main
    git -C "$d" config user.email "t@t"
    git -C "$d" config user.name "t"
    git -C "$d" config commit.gpgsign false
    printf '%s\n' "$d"
}

writef() {  # writef <dir> <path> <content-with-%b-escapes>
    local d="$1" p="$2" c="$3"
    mkdir -p "$d/$(dirname "$p")"
    printf '%b' "$c" > "$d/$p"
}

commit_base() {  # commit_base <dir> <message>
    git -C "$1" add -A
    git -C "$1" commit -q -m "$2"
}

# --- unverändert → keine Änderungen ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
run_script "$d" main
expect 0 "keine Änderungen"

# --- G1: level 8 → 6 gesenkt ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan.neon" "parameters:\n    level: 6\n"
run_script "$d" main
expect 1 "von 8 auf 6 gesenkt"

# --- G1: level 6 → 8 angehoben → kein Befund ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 6\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- G1: neuer ignoreErrors-Eintrag ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    ignoreErrors:\n        - MyClass::m()\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan.neon" "parameters:\n    ignoreErrors:\n        - MyClass::m()\n        - OtherClass::o()\n"
run_script "$d" main
expect 1 "ignoreErrors"

# --- G2: Baseline count 3 → 5 ---
d="$(new_repo)"
writef "$d" "phpstan-baseline.neon" \
    "-\n    message: \"a\"\n    count: 2\n    path: src/A.php\n-\n    message: \"b\"\n    count: 1\n    path: src/B.php\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan-baseline.neon" \
    "-\n    message: \"a\"\n    count: 3\n    path: src/A.php\n-\n    message: \"b\"\n    count: 2\n    path: src/B.php\n"
run_script "$d" main
expect 1 "2 neue Fehler"

# --- G2: Baseline count 5 → 3 → kein Befund ---
d="$(new_repo)"
writef "$d" "phpstan-baseline.neon" \
    "-\n    message: \"a\"\n    count: 3\n    path: src/A.php\n-\n    message: \"b\"\n    count: 2\n    path: src/B.php\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan-baseline.neon" \
    "-\n    message: \"a\"\n    count: 2\n    path: src/A.php\n-\n    message: \"b\"\n    count: 1\n    path: src/B.php\n"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- G3: neues <exclude-pattern> ---
d="$(new_repo)"
writef "$d" "phpcs.xml" "<?xml version=\"1.0\"?>\n<ruleset>\n</ruleset>\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpcs.xml" "<?xml version=\"1.0\"?>\n<ruleset>\n    <exclude-pattern>/vendor/*</exclude-pattern>\n</ruleset>\n"
run_script "$d" main
expect 1 "exclude"

# --- G4: mehr <exclude> in der PHPUnit-Konfiguration → Befund; weniger → ok
d="$(new_repo)"
writef "$d" "phpunit.xml.dist" "<phpunit><testsuites><testsuite name=\"u\"><directory>tests</directory></testsuite></testsuites></phpunit>\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpunit.xml.dist" "<phpunit><testsuites><testsuite name=\"u\"><directory>tests</directory><exclude>tests/Langsam</exclude></testsuite></testsuites></phpunit>\n"
run_script "$d" main
expect 1 "[gate-integrity/G4]"

# --- G5: neue @phpstan-ignore-next-line in src/A.php (Zeile 7) ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\n// l2\n// l3\n// l4\n// l5\n// l6\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" "<?php\n// l2\n// l3\n// l4\n// l5\n// l6\n// @phpstan-ignore-next-line\n"
run_script "$d" main
expect 1 "src/A.php:7:"

# --- G5: gleiche Zeichenfolge in der Basis, unverändert → kein Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\n// l2\n// l3\n// l4\n// l5\n// l6\n// @phpstan-ignore-next-line\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" "<?php\n// l2\n// l3\n// l4\n// l5\n// l6\n// @phpstan-ignore-next-line\n// neue Zeile\n"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- G6: allow_failure: true neu ---
d="$(new_repo)"
writef "$d" ".gitlab-ci.yml" "stages:\n    - build\nphpcs:\n    stage: build\n    script:\n        - vendor/bin/phpcs\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" ".gitlab-ci.yml" "stages:\n    - build\nphpcs:\n    stage: build\n    script:\n        - vendor/bin/phpcs\n    allow_failure: true\n"
run_script "$d" main
expect 1 "allow_failure"

# --- G6: Job phpcs: entfernt ---
d="$(new_repo)"
writef "$d" ".gitlab-ci.yml" \
    "phpcs:\n    stage: test\n    script:\n        - vendor/bin/phpcs\ntest:\n    stage: test\n    script:\n        - vendor/bin/phpunit\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" ".gitlab-ci.yml" \
    "test:\n    stage: test\n    script:\n        - vendor/bin/phpunit\n"
run_script "$d" main
expect 1 'Prüf-Job "phpcs" entfernt'

# --- G7: Makefile-Rezeptzeile mit || true neu ---
d="$(new_repo)"
writef "$d" "Makefile" "test:\n\tvendor/bin/phpunit\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "Makefile" "test:\n\tvendor/bin/phpunit\n\tvendor/bin/phpstan || true\n"
run_script "$d" main
expect 1 "|| true"

# --- Ausnahme: G1-Senkung, aber Commit mit Guard-Ausnahme ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpstan.neon" "parameters:\n    level: 6\n"
git -C "$d" add -A
git -C "$d" commit -q -m "Guard-Ausnahme: Level vorübergehend für Migration"
run_script "$d" main
expect 0 "Guard-Ausnahme"
expect_not 0 "BEFUND"

# --- neu angelegtes phpcs-Regelwerk mit Ausschluessen ist keine Abschwaechung ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "phpcs.xml" "<ruleset><exclude-pattern>/vendor/</exclude-pattern></ruleset>\n"
run_script "$d" main
expect 0 "Keine Befunde."

# --- geaenderte Binaerdatei fuehrt nicht zum Absturz ---
d="$(new_repo)"
printf '\377\376\000binaer' > "$d/bild.bin"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
printf '\377\375\001anders' > "$d/bild.bin"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "Traceback"

# --- unversionierte neue Datei src/B.php mit @psalm-suppress ---
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/B.php" "<?php\n// @psalm-suppress AllIssues\nclass B {}\n"
run_script "$d" main
expect 1 "src/B.php:"

# --- basis-ref existiert nicht → 77 ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
run_script "$d" kein-so-existiert-ref
expect 77

# --- kein Git-Repo → 77 ---
d="$(mktemp -d)"
TMPDIRS+=("$d")
run_script "$d" main
expect 77

# --- ein Argument → 2 ---
d="$(new_repo)"
writef "$d" "phpstan.neon" "parameters:\n    level: 8\n"
commit_base "$d" "Basis"
run_script "$d"
expect 2

# --- G8: TODO/Platzhalter in src/ → Hinweis, aber kein Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" "<?php\nclass A { // TODO: später }\n"
run_script "$d" main
expect 0 "Platzhalter"

# --- G8: leerer catch-Block neu → Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) {}
    }
}
'
run_script "$d" main
expect 1 "leerer catch-Block"

# --- G8: leerer catch-Block mit Kommentar внутри → Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) { //egal
 }
    }
}
'
run_script "$d" main
expect 1 "leerer catch-Block"

# --- G8: gefüllter catch-Block → kein Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) { $this->logger->error(…); }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- G8: leerer catch-Block schon in Basis, unverändert → kein Befund ---
d="$(new_repo)"
writef "$d" "src/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) {
        }
    }
}
'
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "src/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) {
        }
    }
}
// zusätzliche Zeile
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- G8: TODO in tests/ → keine Meldung ---
d="$(new_repo)"
writef "$d" "tests/ATest.php" "<?php\nclass ATest {}\n"
commit_base "$d" "Basis"
git -C "$d" checkout -q -b feature
writef "$d" "tests/ATest.php" "<?php\nclass ATest { // TODO: später }\n"
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"
expect_not 0 "Platzhalter"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
