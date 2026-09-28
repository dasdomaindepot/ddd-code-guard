#!/usr/bin/env bash
#
# Selbsttest für check-error-visibility.
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
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-error-visibility"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

RC=0
OUT=""
fail=0

TMPDIRS=()
cleanup() {
    local rc=$?
    for d in "${TMPDIRS[@]:-}"; do
        [ -n "$d" ] && rm -rf "$d" || true
    done
    return $rc
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
            echo "FEHLER: Stichwort „$kw“ nicht in der Ausgabe" >&2
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
            echo "FEHLER: Stichwort „$kw“ nicht erwartet" >&2
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

enable_feature_branch() {  # enable_feature_branch <dir>
    git -C "$1" checkout -q -b feature
}

# --- Befund 1: echo/die im catch, neu im Controller
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            echo $e->getMessage();
            die;
        }
    }
}
'
run_script "$d" main
expect 1 "catch gibt den Fehler direkt aus"
expect 1 "beendet das Skript"

# --- Befund 1: derselbe Code schon in der Basis → Hinweis (Bestand)
d="$(new_repo)"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            echo $e->getMessage();
            die;
        }
    }
}
// zusätzliche Zeile
'
commit_base "$d" "Basis"
enable_feature_branch "$d"
# nur die zusätzliche Zeile wurde oben bereits committed; hier nur die Datei
# unverändert lassen, damit die catch-Zeile Bestand ist — stattdessen fügen wir
# eine neue Zeile AM ANFANG ein, so bleibt die catch-Zeile unverändert (Bestand).
writef "$d" "src/Controller/A.php" '<?php
// neue Zeile oben
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            echo $e->getMessage();
            die;
        }
    }
}
'
run_script "$d" main
expect 0 "(Bestand)"
expect_not 0 "BEFUND"

# --- Befund 1: guard-Kommentar im Body → keine Meldung
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            // guard: erwartet – Legacy-CLI
            echo $e->getMessage();
            die;
        }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"
expect_not 0 "(Bestand)"

# --- Befund 2: Stacktrace in JsonResponse, neu
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
use Symfony\Component\HttpFoundation\JsonResponse;
class A {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) {
            return new JsonResponse(['trace' => $e->getTraceAsString()]);
        }
    }
}
'
run_script "$d" main
expect 1 "Informationsabfluss"

# --- Befund 3: leerer generischer Fang in src/Controller → Befund
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
        }
    }
}
'
run_script "$d" main
expect 1 "generischer catch"
expect 1 "der Fehler verschwindet"

# --- Befund 3: leerer generischer Fang in src/Service → Hinweis, kein Befund
d="$(new_repo)"
writef "$d" "src/Service/B.php" "<?php\nclass B {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Service/B.php" '<?php
class B {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
        }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"
expect 0 "generischer catch"

# --- Befund 3: logger->error mit type:sentry-Handler → keine Meldung
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
writef "$d" "config/packages/monolog.yaml" "monolog:\n    handlers:\n        main:\n            type: sentry\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            $this->logger->error('x', ['e' => $e]);
        }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- spezifischer Typ ohne 1/2 → keine Meldung
d="$(new_repo)"
writef "$d" "src/Service/B.php" "<?php\nclass B {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Service/B.php" '<?php
class B {
    public function m() {
        try {
            foo();
        } catch (\JsonException $e) {
            return null;
        }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"
expect_not 0 "generischer catch"

# --- verschachtelt: äußerer Body wirft weiter, innerer leer → nur innerer
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $outer) {
            throw $outer;
            try {
                bar();
            } catch (\Throwable $inner) {
            }
        }
    }
}
'
run_script "$d" main
expect 1 "der Fehler verschwindet"
expect 1 "BEFUND"

# --- Closure im catch-Body mit eigenem {} → Befund-Zeile korrekt
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            $f = function () { return 1; };
            echo "x";
        }
    }
}
'
run_script "$d" main
expect 1 "BEFUND"

# --- echo nur in einem String → keine Meldung
d="$(new_repo)"
writef "$d" "src/Service/B.php" "<?php\nclass B {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Service/B.php" '<?php
class B {
    public function m() {
        try {
            foo();
        } catch (\Exception $e) {
            $msg = 'kein echo hier';
            return $msg;
        }
    }
}
'
run_script "$d" main
expect 0 "Keine Befunde."
expect_not 0 "BEFUND"

# --- Befund 4: composer.lock sentry, monolog.yaml ohne sentry, logger->error
d="$(new_repo)"
writef "$d" "composer.lock" "{\"packages\": [{\"name\": \"sentry/sentry-symfony\", \"version\": \"1.0.0\", \"required\": true, \"dev\": false}]}\n"
writef "$d" "config/packages/monolog.yaml" "monolog:\n    handlers:\n        main:\n            type: stream\n"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try {
            foo();
        } catch (\Throwable $e) {
            $this->logger->error('x', ['e' => $e]);
        }
    }
}
'
run_script "$d" main
expect 0 "Monolog leitet nicht"
expect 0 "erreicht Sentry nicht"
expect_not 0 "BEFUND"

# --- kein src/ → 77
d="$(new_repo)"
writef "$d" "README.md" "hello\n"
commit_base "$d" "Basis"
run_script "$d" main
expect 77

# --- kein Argument → 2
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
run_script
expect 2

# --- drei Argumente zu viel → 2
d="$(new_repo)"
writef "$d" "src/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
run_script "$d" main extra
expect 2

# --- basis-ref existiert nicht → alles Bestand, Exit 0
d="$(new_repo)"
writef "$d" "src/Controller/A.php" "<?php\nclass A {}\n"
commit_base "$d" "Basis"
enable_feature_branch "$d"
writef "$d" "src/Controller/A.php" '<?php
class A {
    public function m() {
        try { foo(); }
        catch (\Throwable $e) {}
    }
}
'
run_script "$d" nicht-existiert-ref
expect 0
expect_not 0 "BEFUND"

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
