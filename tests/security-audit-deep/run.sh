#!/usr/bin/env bash
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project/docs/security"
cd "$WORK/project"
git init -q
git config user.email test@example.org
git config user.name Test
printf 'print("unverändert")\n' > app.py
printf '/findings.jsonl\n' > docs/security/.gitignore
git add app.py docs/security/.gitignore
git commit -qm init

cat > "$WORK/agent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
agent="$1"; stage="$2"; project="$3"; output="$4"; prompt="$5"
printf '%s:%s:%s\n' "$agent" "$stage" "$(basename "$output")" >> "$project/docs/.guard/security-audit/calls"
if [ "$STUB_QUOTA" = "$stage" ]; then
    echo 'Usage limit reached' >&2
    exit 9
fi
case "$stage" in
  plan)
    count=24
    if [ "$STUB_SHORT_PLAN" = yes ]; then count=23; fi
    for n in $(seq 1 "$count"); do printf '%s. Frage zu Einstieg, Kontrolle und Gegenbeleg über mehrere Dateien\n' "$n"; done > "$output"
    ;;
  historie|bedrohungsmodell) printf 'Ergebnis vorhanden\n' > "$output" ;;
  suche-1) printf '[{"datei":"app.py","zeile":1,"codepfad":"aufruf"}]\n' > "$output" ;;
  suche-*) printf '[]\n' > "$output" ;;
  dubletten|gegenpruefung) printf '[]\n' > "$output" ;;
esac
if [ "$STUB_MUTATE" = "$stage" ]; then printf 'verändert\n' > "$project/app.py"; fi
STUB
chmod +x "$WORK/agent"

run_audit() {
  set +e
  GUARD_SECURITY_AGENT_STUB="$WORK/agent" STUB_QUOTA="$STUB_QUOTA" STUB_MUTATE="$STUB_MUTATE" STUB_SHORT_PLAN="$STUB_SHORT_PLAN" \
    "$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --deep --project "$WORK/project" "$@" > "$WORK/output" 2>&1
  RC=$?
  set -e
}

STUB_QUOTA='' STUB_MUTATE='' STUB_SHORT_PLAN=''
run_audit
[ "$RC" -eq 0 ]
grep -q '1,4 Mio. Tokens' "$WORK/output"
grep -q '45 Minuten' "$WORK/output"
[ "$(wc -l < docs/.guard/security-audit/calls)" -eq 9 ]
[ "$(grep -c '^claude:suche-' docs/.guard/security-audit/calls)" -eq 4 ]
[ "$(find docs/.guard/security-audit -maxdepth 1 -name '*.json' -regextype posix-extended -regex '.*/[0-9a-f]{8}-[0-9a-f-]{27}\.json' | wc -l)" -eq 4 ]
jq -e 'length == 1 and .[0].datei == "app.py"' docs/.guard/security-audit/04-suche.json >/dev/null
[ "$(cat docs/security/findings.jsonl)" = '' ]

: > docs/.guard/security-audit/calls
rm -f docs/.guard/security-audit/05-dubletten.json
STUB_QUOTA=suche-2 run_audit --agent codex
[ "$RC" -ne 0 ]
grep -qi 'Kontingent' "$WORK/output"
! grep -q 'opencode:' docs/.guard/security-audit/calls
[ ! -f docs/.guard/security-audit/05-dubletten.json ]

: > docs/.guard/security-audit/calls
STUB_QUOTA='' STUB_MUTATE=suche-3 run_audit
[ "$RC" -eq 3 ]
grep -q 'UNSAFE SIDE EFFECT' "$WORK/output"

printf 'print("unverändert")\n' > app.py
: > docs/.guard/security-audit/calls
STUB_MUTATE='' STUB_SHORT_PLAN=yes run_audit
[ "$RC" -eq 2 ]
grep -q '24 nummerierte Untersuchungen' "$WORK/output"
[ "$(wc -l < docs/.guard/security-audit/calls)" -eq 3 ]

set +e
"$ROOT/claude/skills/code-quality/bin/code-guard" --deep --project "$WORK/project" > "$WORK/output" 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ]

set +e
"$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --deep --agent opencode --project "$WORK/project" > "$WORK/output" 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ]
grep -q 'nur claude oder codex' "$WORK/output"

echo 'OK: großer Sicherheits-Audit'
