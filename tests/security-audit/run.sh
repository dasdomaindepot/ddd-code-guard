#!/usr/bin/env bash
set -euo pipefail
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/project"
cd "$WORK/project"
git init -q
git config user.email test@example.org
git config user.name Test
printf 'print("unverändert")\n' > app.py
printf '{"require":{"openai/client":"^1"}}\n' > composer.json
mkdir -p templates
mkdir -p docs/security
printf '/findings.jsonl\n' > docs/security/.gitignore
git add app.py composer.json templates docs/security/.gitignore
git commit -qm init

cat > "$WORK/agent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
agent="$1"; stage="$2"; project="$3"; output="$4"; prompt="$5"
printf '%s\n' "$prompt" > "$project/docs/.guard/security-audit/prompt-$stage"
printf '%s:%s\n' "$agent" "$stage" >> "$project/docs/.guard/security-audit/calls"
case "$stage" in
  historie|bedrohungsmodell|plan) printf '%s\n' 'Ergebnis vorhanden' > "$output" ;;
  suche|dubletten) printf '[]\n' > "$output" ;;
  gegenpruefung) printf '[{"fingerabdruck":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","status":"offen","datei":"app.py","zeile":1,"severity":"HIGH","beschreibung":"Vertrauliches Detail","angreifer":"Nutzer","grenze":"Zugriff","wirkung":"Offenlegung"}]\n' > "$output" ;;
esac
if [ -n "${STUB_FINDINGS:-}" ] && [ "$stage" = gegenpruefung ]; then printf '%s\n' "$STUB_FINDINGS" > "$output"; fi
if [ "${STUB_MISSING:-}" = "$stage" ]; then rm -f "$output"; fi
if [ "${STUB_INVALID:-}" = "$stage" ]; then printf '[{"fingerabdruck":42,"status":"offen","datei":"app.py","zeile":1,"beschreibung":"Prüfung"}]\n' > "$output"; fi
if [ "${STUB_MUTATE:-}" = "$stage" ]; then printf 'verändert\n' > "$project/app.py"; fi
STUB
chmod +x "$WORK/agent"

python3 - "$ROOT/claude/skills/code-quality/bin/guard-security-audit" <<'PY'
import importlib.machinery
import os
import sys

audit = importlib.machinery.SourceFileLoader("audit", sys.argv[1]).load_module()
from pathlib import Path
selected = audit.companions(Path.cwd(), False)
assert len(selected) == 3 and all(path.is_absolute() for path in selected)
deep = [path.name for path in audit.companions(Path.cwd(), True)]
assert "AI-AND-LLM.md" in deep and "RESOURCE-EXHAUSTION-AND-AVAILABILITY.md" in deep
assert "VALIDATION-AND-REPORTING.md" in audit.prompt("suche", Path.cwd() / "docs/.guard/security-audit/04-suche.json", Path.cwd() / "docs/.guard/security-audit", audit.companions(Path.cwd(), True), True)
project = "/tmp/test projekt"
message = "Prüfung"
assert audit.agent_command("opencode", project, message) == [
    "opencode", "run", "--auto", "--dir", project, message
]
os.environ["GUARD_SECURITY_OPENCODE_MODEL"] = "test/modell"
assert audit.agent_command("opencode", project, message) == [
    "opencode", "run", "--auto", "--dir", project, "-m", "test/modell", message
]
del os.environ["GUARD_SECURITY_OPENCODE_MODEL"]
assert audit.agent_command("codex", project, message) == [
    "codex", "exec", "--sandbox", "workspace-write", "--cd", project, message
]
assert audit.agent_command("claude", project, message) == [
    "claude", "-p", message, "--permission-mode", "acceptEdits", "--allowedTools",
    "Read", "Grep", "Glob", "Write", "Edit", "Bash(git log:*)", "Bash(git show:*)"
]
PY

run_audit() {
  set +e
  GUARD_SECURITY_AGENT_STUB="$WORK/agent" STUB_MISSING="${STUB_MISSING:-}" STUB_INVALID="${STUB_INVALID:-}" STUB_MUTATE="${STUB_MUTATE:-}" STUB_FINDINGS="${STUB_FINDINGS:-}" \
    "$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --project "$WORK/project" "${@}" > "$WORK/output" 2>&1
  RC=$?
  set -e
}

run_audit
[ "$RC" -eq 0 ]
[ "$(cat docs/.guard/security-audit/calls)" = $'opencode:historie\nopencode:bedrohungsmodell\nopencode:plan\nopencode:suche\nopencode:dubletten\nopencode:gegenpruefung' ]
jq -e '.fingerabdruck and .status == "offen"' docs/security/findings.jsonl >/dev/null
grep -q 'app.py:1' docs/quality-report.md
grep -q 'Fachreferenzen: ATTACK-CLASSES.md, WEB-PROTOCOL-AND-AUTH.md, DATA-ISOLATION-AND-LIFECYCLE.md' "$WORK/output"
grep -q 'WEB-PROTOCOL-AND-AUTH.md' docs/.guard/security-audit/prompt-plan
! grep -q 'CLIENT-SIDE.md' docs/.guard/security-audit/prompt-plan
! grep -q 'Vertrauliches Detail' docs/quality-report.md
[ "$(cat app.py)" = 'print("unverändert")' ]
python3 - "$ROOT/claude/skills/code-quality/bin/guard-security-audit" <<'PY'
import importlib.machinery
import sys
audit = importlib.machinery.SourceFileLoader("audit_merge", sys.argv[1]).load_module()
old = {"sha256:a": {"fingerabdruck": "sha256:a", "status": "verworfen", "begründung": "geprüft"},
       "sha256:b": {"fingerabdruck": "sha256:b", "status": "erledigt"},
       "sha256:c": {"fingerabdruck": "sha256:c", "status": "offen", "severity": "HIGH"}}
new = [{"fingerabdruck": key, "status": "offen", "severity": "LOW"} for key in ("sha256:a", "sha256:b", "sha256:d")]
new.append({"fingerabdruck": "sha256:c", "status": "erledigt"})
merged = {item["fingerabdruck"]: item for item in audit.merge_findings(old, new)}
assert merged["sha256:a"]["status"] == "verworfen"
assert merged["sha256:a"]["begründung"] == "geprüft"
assert merged["sha256:b"]["status"] == "erledigt"
assert merged["sha256:c"]["status"] == "erledigt"
assert merged["sha256:d"]["status"] == "offen"
new = [{"fingerabdruck": "sha256:c", "status": "bedingt", "offene_voraussetzung": "Betreiber prüft Konfiguration"}]
conditional = audit.merge_findings(old, new)[2]
assert conditional["status"] == "bedingt" and "severity" not in conditional
closed = audit.merge_findings({"sha256:c": conditional}, [{"fingerabdruck": "sha256:c", "status": "erledigt", "begründung": "behoben"}])[0]
assert closed["status"] == "erledigt"
PY
if git -c core.excludesFile=/dev/null status --porcelain --untracked-files=all | grep -q 'docs/.guard'; then
    echo 'Stufenordner ist nicht vor Git verborgen' >&2
    exit 1
fi

: > docs/.guard/security-audit/calls
STUB_MISSING=plan run_audit --agent claude
[ "$RC" -ne 0 ]
[ "$(wc -l < docs/.guard/security-audit/calls)" -eq 3 ]
grep -q 'Stufenergebnis fehlt' "$WORK/output"

: > docs/.guard/security-audit/calls
STUB_INVALID=gegenpruefung run_audit
[ "$RC" -eq 2 ]
grep -q 'Ungültiger Sicherheitsfund' "$WORK/output"

: > docs/.guard/security-audit/calls
STUB_MUTATE=suche run_audit --agent codex
[ "$RC" -eq 3 ]
[ "$(wc -l < docs/.guard/security-audit/calls)" -eq 4 ]
grep -q 'UNSAFE SIDE EFFECT' "$WORK/output"

printf 'print("unverändert")\n' > app.py
FP='sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
CONDITIONAL="$(jq -nc --arg fp "$FP" '[{fingerabdruck:$fp,status:"bedingt",datei:"app.py",zeile:1,beschreibung:"Prüfung",offene_voraussetzung:"Betreiber prüft Konfiguration gefahrlos"}]')"
STUB_FINDINGS="$CONDITIONAL" run_audit
[ "$RC" -eq 0 ]
grep -q '## Offene Voraussetzungen' docs/quality-report.md
grep -q '\*\*Verdikt:\*\* YELLOW' docs/quality-report.md
grep -q 'bedingte Sicherheitsfunde' docs/quality-report.md
jq -e 'select(.status == "bedingt" and (has("severity") | not))' docs/security/findings.jsonl >/dev/null

expect_invalid() {
  STUB_FINDINGS="$1" run_audit
  [ "$RC" -eq 2 ] || { cat "$WORK/output" >&2; exit 1; }
  grep -Eq "Fund [12] \($FP\)" "$WORK/output"
}
expect_invalid "$(jq -c '.[0] | del(.offene_voraussetzung) | [. ]' <<<"$CONDITIONAL")"
expect_invalid "$(jq -c '.[0] | .severity="HIGH" | [.]' <<<"$CONDITIONAL")"
expect_invalid "$(jq -cn --argjson item "$CONDITIONAL" '$item + $item')"
OPEN="$(jq -c '.[0] | .status="offen" | .severity="MEDIUM" | .angreifer="Nutzer" | .grenze="Rolle" | .wirkung="Datenzugriff" | del(.offene_voraussetzung) | [. ]' <<<"$CONDITIONAL")"
expect_invalid "$(jq -c '.[0] | del(.angreifer) | [. ]' <<<"$OPEN")"
expect_invalid "$(jq -c '.[0] | .datei="fehlt.py" | [.]' <<<"$OPEN")"
expect_invalid "$(jq -c '.[0] | .zeile=99 | [.]' <<<"$OPEN")"
STUB_FINDINGS="$OPEN" run_audit
[ "$RC" -eq 0 ]
jq -e 'select(.status == "offen" and .severity == "MEDIUM")' docs/security/findings.jsonl >/dev/null

printf 'andere-datei.log' > docs/security/.gitignore
run_audit
[ "$RC" -eq 0 ]
grep -qx 'andere-datei.log' docs/security/.gitignore
grep -qx 'findings.jsonl' docs/security/.gitignore
grep -q 'docs/security/.gitignore.*ergänzt' "$WORK/output"

rm docs/security/.gitignore
git rm -q --cached docs/security/.gitignore
run_audit
[ "$RC" -eq 0 ]
grep -qx 'findings.jsonl' docs/security/.gitignore
grep -qx 'coverage-ledger.json' docs/security/.gitignore
grep -q 'docs/security/.gitignore.*angelegt' "$WORK/output"

git add -f docs/security/findings.jsonl
run_audit
[ "$RC" -eq 2 ]
grep -q 'docs/security/findings.jsonl ist versioniert' "$WORK/output"

echo 'OK: Sicherheits-Audit-Stufen und Schreibgrenze'
