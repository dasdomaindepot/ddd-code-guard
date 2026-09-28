#!/usr/bin/env bash
#
# Regelabdeckung der Selbsttests.
#
# Fährt alle tests/*/run.sh und schneidet dabei mit, welche Regel-IDs
# (z. B. house-rules/R3) mindestens einmal einen Befund oder Hinweis ausgelöst
# haben. Eine Regel, die im ganzen Testlauf nie auslöst, hat keinen
# Verstoß-Fall – sie könnte kaputt sein, ohne dass ein Test rot wird.
#
#   bash tests/rule-coverage.sh           # Liste der Regeln ohne Verstoß-Fall
#   bash tests/rule-coverage.sh --strict  # Exit 1, wenn eine Regel fehlt
#
# Die deklarierten Regeln stammen aus den Zeilen `RULE = "…"` der Check-Scripts.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/../claude/skills/code-quality/bin"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

rot=0
for t in "$HERE"/*/run.sh; do
    if ! GUARD_RULE_LOG="$LOG" bash "$t" >/dev/null 2>&1; then
        echo "ROT: $(basename "$(dirname "$t")") — Abdeckung unvollständig gemessen" >&2
        rot=1
    fi
done

# Deklarierte Regeln: CHECK_ID je Script plus alle RULE-Zuweisungen darin.
deklariert="$(
    for f in "$BIN"/check-*; do
        check="$(grep -oE '^CHECK_ID = "[^"]+"' "$f" 2>/dev/null | sed -E 's/.*"(.*)"/\1/')"
        [ -n "$check" ] || continue
        grep -oE '^\s+RULE = "[^"]+"' "$f" | sed -E 's/.*"(.*)"/\1/' | sed "s#^#$check/#"
    done | sort -u
)"
ausgeloest="$(sort -u "$LOG")"

fehlend="$(comm -23 <(printf '%s\n' "$deklariert") <(printf '%s\n' "$ausgeloest"))"
gesamt=$(printf '%s\n' "$deklariert" | grep -c .)
n_fehlend=$(printf '%s\n' "$fehlend" | grep -c .)

echo "Regeln: $gesamt deklariert, $((gesamt - n_fehlend)) im Testlauf ausgelöst."
if [ "$n_fehlend" -gt 0 ]; then
    echo "Ohne Verstoß-Fall:"
    printf '  %s\n' $fehlend
fi

if [ "$rot" -eq 1 ]; then
    exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$n_fehlend" -gt 0 ]; then
    exit 1
fi
exit 0
