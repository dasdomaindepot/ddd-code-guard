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
printf 'findings.jsonl\ncoverage-ledger.json\n' > docs/security/.gitignore
git add . && git commit -qm init

cat > "$WORK/agent" <<'STUB'
#!/usr/bin/env python3
import json, os, pathlib, re, sys
agent, stage, project, output, message = sys.argv[1:]
root = pathlib.Path(project)
with (root / 'docs/.guard/security-audit/calls').open('a') as log:
    log.write(f'{agent}:{stage}\n')
if os.environ.get('STUB_QUOTA') == stage:
    print('Usage limit reached', file=sys.stderr)
    sys.exit(9)
path = pathlib.Path(output)
if stage == 'plan':
    path.write_text('Konkreter Plan\n')
    count = int(os.environ.get('STUB_COUNT', '8'))
    units = [{'id': f'unit-{i}', 'oberflaeche': 'Einstieg', 'grenze': 'Rolle',
              'angriffsklasse': 'Autorisierung', 'dateien': ['app.py'], 'prioritaet': 1}
             for i in range(count)]
    if os.environ.get('STUB_DUPLICATE') == 'yes':
        units[-1]['id'] = units[0]['id']
    (path.parent / '03-ledger.json').write_text(json.dumps(units))
elif stage.startswith('suche-'):
    ids = re.findall(r'"id": "(unit-[0-9]+|neu)"', message)
    if os.environ.get('STUB_OMIT') == 'yes' and ids:
        ids = ids[1:]
    path.write_text(json.dumps({'einheiten': [{'id': i, 'status': 'abgedeckt',
        'begründung': 'Quellpfad geprüft'} for i in ids], 'kandidaten': []}))
elif stage == 'kritik':
    extra = []
    if os.environ.get('STUB_EXTRA') == 'yes':
        extra = [{'id':'neu','oberflaeche':'Neu','grenze':'Rolle',
                  'angriffsklasse':'Autorisierung','dateien':['app.py'],'prioritaet':1}]
    path.write_text(json.dumps(extra))
elif stage in ('dubletten', 'gegenpruefung'):
    path.write_text('[]\n')
else:
    path.write_text('Ergebnis vorhanden\n')
if os.environ.get('STUB_MUTATE') == stage:
    (root / 'app.py').write_text('verändert\n')
STUB
chmod +x "$WORK/agent"

run_audit() {
    set +e
    GUARD_SECURITY_AGENT_STUB="$WORK/agent" STUB_COUNT="$STUB_COUNT" STUB_DUPLICATE="$STUB_DUPLICATE" \
      STUB_OMIT="$STUB_OMIT" STUB_EXTRA="$STUB_EXTRA" STUB_QUOTA="$STUB_QUOTA" STUB_MUTATE="$STUB_MUTATE" \
      "$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --profile deep --project "$WORK/project" "$@" > "$WORK/output" 2>&1
    RC=$?
    set -e
}

STUB_COUNT=8 STUB_DUPLICATE='' STUB_OMIT='' STUB_EXTRA='' STUB_QUOTA='' STUB_MUTATE=''
run_audit
[ "$RC" -eq 0 ] || { cat "$WORK/output"; exit 1; }
grep -q '1,4 Mio. Tokens' "$WORK/output"
[ "$(wc -l < docs/.guard/security-audit/calls)" -eq 10 ]
jq -e 'length == 8 and all(.[]; .status == "abgedeckt")' docs/security/coverage-ledger.json >/dev/null
grep -q '## Abdeckung' docs/quality-report.md

run_audit
[ "$RC" -eq 0 ]
jq -e 'all(.[]; .prioritaet == 3)' docs/security/coverage-ledger.json >/dev/null
STUB_OMIT=yes run_audit
[ "$RC" -eq 0 ]
jq -e 'any(.[]; .status == "offen")' docs/security/coverage-ledger.json >/dev/null
STUB_OMIT='' STUB_EXTRA=yes run_audit
[ "$RC" -eq 0 ]
[ "$(grep -c '^claude:suche-5$' docs/.guard/security-audit/calls)" -eq 1 ]
STUB_OMIT=yes STUB_EXTRA=yes run_audit
[ "$RC" -eq 0 ]
jq -e 'any(.[]; .id == "neu" and .status == "zurückgestellt")' docs/security/coverage-ledger.json >/dev/null
STUB_OMIT='' STUB_EXTRA=yes run_audit --profile standard
[ "$RC" -eq 0 ]
jq -e 'any(.[]; .id == "neu" and .status == "zurückgestellt")' docs/security/coverage-ledger.json >/dev/null
[ "$(grep -c '^claude:suche-5$' docs/.guard/security-audit/calls)" -eq 2 ]

STUB_OMIT='' STUB_EXTRA='' STUB_COUNT=7 run_audit
[ "$RC" -eq 2 ]
grep -q 'mindestens 8' "$WORK/output"
STUB_COUNT=8 STUB_DUPLICATE=yes run_audit
[ "$RC" -eq 2 ]
grep -q 'Doppelte Coverage-ID' "$WORK/output"
STUB_DUPLICATE='' STUB_QUOTA=suche-2 run_audit --agent codex
[ "$RC" -eq 2 ]
grep -qi Kontingent "$WORK/output"
STUB_QUOTA='' STUB_MUTATE=suche-3 run_audit
[ "$RC" -eq 3 ]
grep -q 'UNSAFE SIDE EFFECT' "$WORK/output"
set +e
"$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --deep --agent opencode --project "$WORK/project" > "$WORK/output" 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ]
echo 'OK: Coverage-Ledger im Deep-Audit'
