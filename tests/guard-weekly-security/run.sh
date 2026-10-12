#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/project" 2>/dev/null
cd "$WORK/project"
echo code > app.py
echo 'docs/.guard/' > .gitignore
git add . && git commit -qm init && git push -q origin main

cat > "$WORK/guard" <<'STUB'
#!/usr/bin/env bash
project=""
audit=0
for ((i=1;i<=$#;i++)); do
    arg="${!i}"
    [ "$arg" != "--project" ] || { j=$((i+1)); project="${!j}"; }
    [ "$arg" != "--security-audit" ] || audit=1
    [ "$arg" != "--deep" ] || exit 99
done
if [ "$audit" -eq 1 ]; then
    mkdir -p "$project/docs/security"
    echo 'findings.jsonl' > "$project/docs/security/.gitignore"
    echo '{"fingerabdruck":"sha256:0000000000000000000000000000000000000000000000000000000000000001","status":"verworfen","datei":"app.py","zeile":1,"beschreibung":"geprüft"}' > "$project/docs/security/findings.jsonl"
    echo '# Sicherheitsbericht' > "$project/docs/security/audit-report.md"
else
    mkdir -p "$project/docs/.guard"
    echo '{"verdict":"GREEN","checks":[]}' > "$project/docs/.guard/results.json"
fi
STUB
chmod +x "$WORK/guard"
export GUARD_WEEKLY_CODE_GUARD="$WORK/guard"
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/opencode"
chmod +x "$WORK/bin/opencode"
export PATH="$WORK/bin:$PATH"

"$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$PWD" --security-audit --agent opencode --no-push > "$WORK/out" 2>&1
git show develop:docs/security/audit-report.md | grep -q '^guard_status: open$'
! git cat-file -e develop:docs/quality-report.md 2>/dev/null
if [ -n "$(git status --porcelain)" ]; then
    git status --porcelain -uall >&2
    cat "$WORK/out" >&2
    exit 1
fi

set +e
"$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$PWD" --security-audit --agent opencode --no-push > "$WORK/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 11 ]
grep -q 'Kalendermonat' "$WORK/out"

"$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$PWD" --agent none --no-push > "$WORK/out" 2>&1
git show develop:docs/quality-report.md | grep -q '^guard_status: open$'
git show develop:docs/security/audit-report.md | grep -q '^guard_status: open$'
echo 'OK: monatlicher Sicherheitszustand und Wochenreport getrennt'
