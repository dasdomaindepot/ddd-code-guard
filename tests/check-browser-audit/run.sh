#!/usr/bin/env bash
#
# Selbsttest für check-browser-audit.
#
# Startet je Fall einen lokalen Server und fährt den Browser-Check ohne Lighthouse
# (GUARD_SKIP_LIGHTHOUSE=1, sonst dauert jeder Fall zehnmal so lange). Ohne Node
# oder Chrome wird der Test übersprungen statt rot — der Check meldet dann 77.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/claude/skills/code-quality/bin/check-browser-audit"
export GUARD_SKIP_LIGHTHOUSE=1

PIDS=()
fail=0
cleanup() { for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }

start_server() {
    local port; port="$(free_port)"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$1" >/dev/null 2>&1 &
    PIDS+=("$!")
    for _ in $(seq 1 50); do
        python3 -c "import socket,sys; s=socket.socket(); sys.exit(s.connect_ex(('127.0.0.1',$port)))" && break
        sleep 0.1
    done
    printf '%s' "$port"
}

RC=0; OUT=""
run_script() { if OUT="$("$SCRIPT" "$@" 2>&1)"; then RC=0; else RC=$?; fi; }

expect() {
    local exp_rc="$1"; shift
    case "$exp_rc" in ''|*[!0-9]*) echo "FEHLER: expect ohne Exit-Code aufgerufen: $exp_rc" >&2; fail=1; return ;; esac
    if [ "$RC" -ne "$exp_rc" ]; then echo "FEHLER: erwarteter Exit $exp_rc, aber $RC" >&2; printf '%s\n' "$OUT" >&2; fail=1; fi
    local kw
    for kw in "$@"; do
        printf '%s' "$OUT" | grep -qF -- "$kw" || { echo "FEHLER: Stichwort „$kw“ nicht in der Ausgabe" >&2; fail=1; }
    done
}

expect_not() {
    local kw
    for kw in "$@"; do
        if printf '%s' "$OUT" | grep -qF -- "$kw"; then echo "FEHLER: Stichwort „$kw“ unerwartet in der Ausgabe" >&2; fail=1; fi
    done
}

# Ohne Browser nicht messbar: Test überspringen, nicht rot werden.
port="$(start_server "$HERE/fixtures/gut")"
run_script "http://127.0.0.1:$port"
if [ "$RC" -eq 77 ] && printf '%s' "$OUT" | grep -qE "node nicht gefunden|Chrome"; then
    echo "ÜBERSPRUNGEN: $OUT"
    exit 0
fi
expect 0 "Keine Befunde." "ohne WCAG-2.2-AA-Verstöße"
expect_not "sfwdt" "button-name"

port="$(start_server "$HERE/fixtures/schlecht")"
run_script "http://127.0.0.1:$port"
expect 1 "color-contrast (serious)" "label (critical)"

# Inhalt, der erst per JavaScript entsteht, wird geprüft.
port="$(start_server "$HERE/fixtures/spa")"
run_script "http://127.0.0.1:$port"
expect 1 "image-alt (critical)"

# Port ohne Server → nicht messbar; ohne Argument → Nutzungsfehler.
run_script "http://127.0.0.1:$(free_port)"
expect 77
run_script
expect 2

if [ "$fail" -eq 0 ]; then echo "OK: alle Fälle bestanden"; exit 0; fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
