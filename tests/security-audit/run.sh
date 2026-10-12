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
mkdir -p docs/security
printf '/findings.jsonl\n' > docs/security/.gitignore
git add app.py docs/security/.gitignore
git commit -qm init

cat > "$WORK/agent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
agent="$1"; stage="$2"; project="$3"; output="$4"; prompt="$5"
printf '%s:%s\n' "$agent" "$stage" >> "$project/docs/.guard/security-audit/calls"
case "$stage" in
  historie|bedrohungsmodell|plan) printf '%s\n' 'Ergebnis vorhanden' > "$output" ;;
  suche|dubletten) printf '[]\n' > "$output" ;;
  gegenpruefung) printf '[{"fingerabdruck":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","status":"offen","datei":"app.py","zeile":1,"severity":"HIGH","beschreibung":"Vertrauliches Detail"}]\n' > "$output" ;;
esac
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
  GUARD_SECURITY_AGENT_STUB="$WORK/agent" STUB_MISSING="${STUB_MISSING:-}" STUB_INVALID="${STUB_INVALID:-}" STUB_MUTATE="${STUB_MUTATE:-}" \
    "$ROOT/claude/skills/code-quality/bin/code-guard" --security-audit --project "$WORK/project" "${@}" > "$WORK/output" 2>&1
  RC=$?
  set -e
}

run_audit
[ "$RC" -eq 0 ]
[ "$(cat docs/.guard/security-audit/calls)" = $'opencode:historie\nopencode:bedrohungsmodell\nopencode:plan\nopencode:suche\nopencode:dubletten\nopencode:gegenpruefung' ]
jq -e '.fingerabdruck and .status == "offen"' docs/security/findings.jsonl >/dev/null
grep -q 'app.py:1' docs/quality-report.md
! grep -q 'Vertrauliches Detail' docs/quality-report.md
[ "$(cat app.py)" = 'print("unverändert")' ]
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
[ "$(cat docs/security/.gitignore)" = 'findings.jsonl' ]
grep -q 'docs/security/.gitignore.*angelegt' "$WORK/output"

git add -f docs/security/findings.jsonl
run_audit
[ "$RC" -eq 2 ]
grep -q 'docs/security/findings.jsonl ist versioniert' "$WORK/output"

echo 'OK: Sicherheits-Audit-Stufen und Schreibgrenze'
