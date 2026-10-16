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
printf 'print("ok")\n' > app.py
printf 'findings.jsonl\ncoverage-ledger.json\n' > docs/security/.gitignore
git add . && git commit -qm init

cat > "$WORK/agent" <<'STUB'
#!/usr/bin/env python3
import json, os, pathlib, sys
agent, stage, project, output, prompt = sys.argv[1:]
assert stage == 'cf'
run = pathlib.Path(output).parent
trace = [{'kind':'entrypoint','file':'app.py','line':1,'scope':'Nutzer','description':'Einstieg'},
         {'kind':'sink','file':'app.py','line':1,'scope':'Daten','description':'Senke'}]
evidence = [{'file':'app.py','line':1,'description':'Quellbeleg'}]
base = {'trace':trace, 'evidence':evidence, 'description':'Geprüfter Codepfad'}
records = [
    {**base, 'verdict':'confirmed','fingerprint':'cf-confirmed','title':'Berechtigung',
     'root_cause':'Kontrolle fehlt','intended_behavior':'Rolle begrenzt Zugriff',
     'conditions':[], 'execution':{'attacker_perspective':'Nutzer','payloads':['Test'],
       'instructions':['Statischen Pfad lesen'],'observed_result':'Daten sichtbar'},
     'remediation':{'strategy':'Rolle prüfen'},
     'severity':{'likelihood':{'score':'high','reason':'Erreichbar'},
       'impact':{'score':'high','reason':'Datenzugriff'},'overall_severity':'high'},
     'confidence':{'score':'high','reason':'Quellpfad'}},
    {**base, 'verdict':'needs_validation','fingerprint':'cf-conditional','title':'Konfiguration',
     'claimed_root_cause':'Option unklar','blockers':['Betreiberkonfiguration fehlt'],
     'validation_plan':{'deployment':'Betreiber prüft Konfiguration'}},
    {**base, 'verdict':'rejected','fingerprint':'cf-rejected','title':'Widerlegt',
     'claimed_root_cause':'Vermutete Lücke','reason':'Kontrolle vorhanden'}]
if os.environ.get('STUB_MISSING') != 'yes':
    (run/'findings.json').write_text(json.dumps(sorted(records, key=lambda item: item['fingerprint'])))
(run/'coverage-ledger.json').write_text('[]\n')
STUB
chmod +x "$WORK/agent"
run_audit() {
    set +e
    GUARD_SECURITY_AGENT_STUB="$WORK/agent" STUB_MISSING="${STUB_MISSING:-}" \
      "$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --engine cf --project "$WORK/project" "$@" > "$WORK/out" 2>&1
    RC=$?
    set -e
}
run_audit
[ "$RC" -eq 0 ] || { cat "$WORK/out"; exit 1; }
jq -se 'length == 3 and any(.[]; .status == "offen" and .severity == "HIGH") and
        any(.[]; .status == "bedingt" and .offene_voraussetzung == "Betreiberkonfiguration fehlt") and
        any(.[]; .status == "verworfen" and ."begründung" == "Kontrolle vorhanden")' docs/security/findings.jsonl >/dev/null
grep -q '## Sicherheitsfunde' docs/quality-report.md
[ -f docs/.guard/security-audit/cf/run-1/findings.json ]
STUB_MISSING=yes run_audit
[ "$RC" -eq 2 ]
grep -q 'cf-Ergebnis fehlt' "$WORK/out"
set +e
"$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --engine cf --agent opencode --project "$WORK/project" > "$WORK/out" 2>&1
RC=$?
set -e
[ "$RC" -eq 2 ]

# Echter Agentenweg ohne Stub: Befehlsaufbau und Zeitlimits je Stufe.
python3 - "$ROOT/claude/skills/code-quality/bin/guard-security-audit" "$WORK/project" <<'PY'
import importlib.machinery, importlib.util, subprocess, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("audit", sys.argv[1])
spec = importlib.util.spec_from_loader("audit", loader)
audit = importlib.util.module_from_spec(spec)
loader.exec_module(audit)
project = Path(sys.argv[2])
calls = []
def fake_run(command, **kwargs):
    calls.append((command, kwargs))
    return subprocess.CompletedProcess(command, 0, "", "")
audit.subprocess.run = fake_run
audit.os.environ.pop("GUARD_SECURITY_AGENT_STUB", None)
audit.os.environ.pop("GUARD_SECURITY_CF_TIMEOUT", None)
audit.os.environ.pop("GUARD_SECURITY_CALL_TIMEOUT", None)
audit.call_agent("claude", "cf", project, project / "out.json", "nachricht")
command, kwargs = calls[-1]
assert command[:3] == ["claude", "-p", "nachricht"], command
assert "Task" in command and kwargs["cwd"] == project and kwargs["timeout"] == 14400, (command, kwargs)
audit.call_agent("claude", "plan", project, project / "out.json", "nachricht")
command, kwargs = calls[-1]
assert "Task" not in command and kwargs["timeout"] == 1800, (command, kwargs)
audit.call_agent("codex", "suche-1", project, project / "out.json", "nachricht")
command, _ = calls[-1]
assert command[:5] == ["codex", "exec", "--sandbox", "workspace-write", "--cd"] and command[5] == str(project), command
audit.call_agent("opencode", "plan", project, project / "out.json", "nachricht")
command, _ = calls[-1]
assert command[:5] == ["opencode", "run", "--auto", "--dir", str(project)] and command[-1] == "nachricht", command
audit.os.environ["GUARD_SECURITY_CF_TIMEOUT"] = "0"
audit.call_agent("claude", "cf", project, project / "out.json", "nachricht")
assert calls[-1][1]["timeout"] is None
PY

echo 'OK: cf-Engine und Adapter'
