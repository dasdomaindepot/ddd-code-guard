#!/usr/bin/env bash
#
# Selbsttest für check-third-party.
#
# Startet für jeden Fixture-Ordner einen lokalen Server, fährt das Script gegen
# die lokale URL und prüft Exit-Code und Ausgabe. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/check-third-party"
FIX="$HERE/fixtures"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

PIDS=()
fail=0

cleanup() {
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

wait_port() {
    local port="$1" i
    for i in $(seq 1 50); do
        if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(0.2); sys.exit(0 if s.connect_ex(('127.0.0.1',$port))==0 else 1)"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

start_server() {
    local dir="$1" port pid
    port="$(free_port)"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
    pid=$!
    PIDS+=("$pid")
    wait_port "$port" || { echo "FEHLER: Server für $dir antwortet nicht" >&2; exit 1; }
    printf '%s' "$port"
}

RC=0
OUT=""

run_script() {
    if OUT="$("$SCRIPT" "$@" 2>&1)"; then
        RC=0
    else
        RC=$?
    fi
}

expect() {
    local exp_rc="$1"; shift
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

# --- guter Fall: selbst gehosteter Schrift, kein Tracker -----------------------------
port="$(start_server "$FIX/gut")"
run_script "http://127.0.0.1:$port"
expect 0 "keine fremden Quellen beim ersten Aufruf"

# --- Google Fonts direkt über <link> ------------------------------------------------
port="$(start_server "$FIX/fonts")"
run_script "http://127.0.0.1:$port"
expect 1 "Google Fonts"

# --- Google Fonts über verlinktes Stylesheet (@import) ------------------------------
port="$(start_server "$FIX/fonts-css")"
run_script "http://127.0.0.1:$port"
expect 1 "über /app.css"

# --- Tracker ohne Consent: Analytics, Maps, YouTube ---------------------------------
port="$(start_server "$FIX/tracker")"
run_script "http://127.0.0.1:$port"
expect 1 \
    "Google Analytics/Tag Manager" \
    "Google Maps" \
    "YouTube"

# --- Consent-Tool mildert NICHT ab: Script + YouTube werden gemeldet -----------------
port="$(start_server "$FIX/consent")"
run_script "http://127.0.0.1:$port"
expect 1 \
    "app.usercentrics.eu" \
    "YouTube"

# --- CDN-Bibliothek ohne bekannten Anbieter: Befund, lokal ausliefern ----------------
port="$(start_server "$FIX/cdn")"
run_script "http://127.0.0.1:$port"
expect 1 "code.jquery.com"

# --- iframe ohne youtube-nocookie: lädt beim ersten Aufruf, Zwei-Klick --------------
port="$(start_server "$FIX/nocookie")"
run_script "http://127.0.0.1:$port"
expect 1 "youtube-nocookie"

# --- srcset: fremde Bild-URL wird gemeldet ------------------------------------------
port="$(start_server "$FIX/srcset")"
run_script "http://127.0.0.1:$port"
expect 1 "bilder.fremd.example"

# --- blockiert (data-src / type=text/plain): nichts wird geladen ---------------------
port="$(start_server "$FIX/blockiert")"
run_script "http://127.0.0.1:$port"
expect 0

# --- JSON-LD mit Links auf fremde Profile: Strukturdaten laden nichts --------------
port="$(start_server "$FIX/jsonld")"
run_script "http://127.0.0.1:$port"
expect 0 "keine fremden Quellen"
expect_not 0 "youtube.com" "instagram.com"

# --- mehrere Seiten über sitemap: Formatierungsregel für >3 Seiten ------------------
port="$(start_server "$FIX/mehrerer-seiten")"
run_script "http://127.0.0.1:$port"
expect 1 "und 3 weiteren Seiten"

# --- Freigabe aus dem Projektprofil: statt Befund eine `ok … freigegeben …` ----------
port="$(start_server "$FIX/allowlist")"
run_script "http://127.0.0.1:$port" "$FIX/allowlist"
expect 0 "freigegeben"

# --- Freigabe ohne Grund: Hinweis, der Eintrag wird nicht berücksichtigt -------------
port="$(start_server "$FIX/no-grund")"
run_script "http://127.0.0.1:$port" "$FIX/no-grund"
expect 1 "ohne Grund"

# --- nicht erreichbar: Port ohne Server ----------------------------------------------
dead_port="$(free_port)"
run_script "http://127.0.0.1:$dead_port"
expect 77

# --- Nutzungsfehler: kein Argument --------------------------------------------------
run_script
expect 2

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: einige Fälle haben nicht bestanden" >&2
exit 1
