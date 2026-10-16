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
printf '%s\n' "$*" >> "$GUARD_CALLS"
if [ "$audit" -eq 1 ]; then
    mkdir -p "$project/docs/security"
    echo 'findings.jsonl' > "$project/docs/security/.gitignore"
    if [ "${STUB_OPEN:-}" = yes ]; then
        echo '{"fingerabdruck":"sha256:0000000000000000000000000000000000000000000000000000000000000001","status":"offen","severity":"MEDIUM","datei":"app.py","zeile":1,"beschreibung":"Prüfung","angreifer":"Nutzer","grenze":"Rolle","wirkung":"Datenzugriff"}' > "$project/docs/security/findings.jsonl"
    elif [ "${STUB_CONDITIONAL:-}" = yes ]; then
        echo '{"fingerabdruck":"sha256:0000000000000000000000000000000000000000000000000000000000000001","status":"bedingt","datei":"app.py","zeile":1,"beschreibung":"Prüfung","offene_voraussetzung":"Betreiber prüft die Konfiguration"}' > "$project/docs/security/findings.jsonl"
    else
        echo '{"fingerabdruck":"sha256:0000000000000000000000000000000000000000000000000000000000000001","status":"verworfen","datei":"app.py","zeile":1,"beschreibung":"geprüft"}' > "$project/docs/security/findings.jsonl"
    fi
    echo '# Sicherheitsbericht' > "$project/docs/security/audit-report.md"
else
    mkdir -p "$project/docs/.guard"
    echo '{"verdict":"GREEN","checks":[]}' > "$project/docs/.guard/results.json"
fi
STUB
chmod +x "$WORK/guard"
export GUARD_WEEKLY_CODE_GUARD="$WORK/guard"
export GUARD_CALLS="$WORK/guard-calls"
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/opencode"
chmod +x "$WORK/bin/opencode"
export PATH="$WORK/bin:$PATH"

set +e
"$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$PWD" --security-audit --security-profile deep --agent opencode > "$WORK/invalid.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -q 'claude oder --agent codex' "$WORK/invalid.out"

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

cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
method=GET output='' body='' url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -X) method="$2"; shift 2 ;;
        -o) output="$2"; shift 2 ;;
        --data-binary) body="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
if [ "$method" = GET ]; then
    if [ -n "${VIKUNJA_TASK_TITLE:-}" ] && [[ "$url" != *'page=2'* ]]; then
        jq -nc --arg title "$VIKUNJA_TASK_TITLE" '[{id:100,title:$title,done:false}]' > "$output"
    else printf '[]' > "$output"; fi
else
    printf '%s\n' "$body" >> "$VIKUNJA_LOG"
    printf '{"id":1}' > "$output"
fi
printf 200
STUB
chmod +x "$WORK/bin/curl"
git clone -q "$WORK/origin.git" "$WORK/conditional" 2>/dev/null
STUB_CONDITIONAL=yes VIKUNJA_LOG="$WORK/vikunja.log" VIKUNJA_BASE_URL="http://example.invalid" VIKUNJA_API_TOKEN=testtoken \
    "$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$WORK/conditional" --security-audit --agent opencode --vikunja-project 81 --no-push > "$WORK/conditional.out" 2>&1
grep -q 'Prüfen: Sicherheitsfund' "$WORK/vikunja.log"
! grep -q 'Schwere:' "$WORK/vikunja.log"
VIKUNJA_TASK_TITLE="[Guard] conditional: Prüfen: Sicherheitsfund (sha256:0000000000000000000000000000000000000000000000000000000000000001)" \
STUB_OPEN=yes VIKUNJA_LOG="$WORK/vikunja.log" VIKUNJA_BASE_URL="http://example.invalid" VIKUNJA_API_TOKEN=testtoken \
    "$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$WORK/conditional" --security-audit --agent opencode --vikunja-project 81 --no-push --force > "$WORK/transition.out" 2>&1
grep -q 'Von bedingt zu offen' "$WORK/vikunja.log"

git clone -q "$WORK/origin.git" "$WORK/deep" 2>/dev/null
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/claude"
chmod +x "$WORK/bin/claude"
"$ROOT/claude/skills/code-quality/bin/guard-weekly" --project "$WORK/deep" --security-audit --security-profile deep --agent claude --no-push > "$WORK/deep.out" 2>&1
grep -q -- '--profile deep' "$GUARD_CALLS"
echo 'OK: monatlicher Sicherheitszustand und Wochenreport getrennt'
