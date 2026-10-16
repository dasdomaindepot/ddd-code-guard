#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/gut" "$WORK/fehler"
printf '%s\n%s\n' "$WORK/gut" "$WORK/fehler" > "$WORK/projects.txt"
cat > "$WORK/weekly" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$*" in *'/fehler'*) exit 13 ;; esac
exit 0
STUB
chmod +x "$WORK/weekly"
export CALLS="$WORK/calls"
export GUARD_SECURITY_ALL_WEEKLY="$WORK/weekly"
set +e
"$ROOT/claude/skills/code-quality/bin/guard-security-all" --projects "$WORK/projects.txt" --security-profile deep --agent claude > "$WORK/out" 2>&1
RC=$?
set -e
[ "$RC" -eq 1 ]
[ "$(wc -l < "$CALLS")" -eq 2 ]
grep -q 'Exit 13' "$WORK/out"
: > "$CALLS"
"$ROOT/claude/skills/code-quality/bin/guard-security-all" --projects "$WORK/projects.txt" --dry-run --security-engine cf > "$WORK/out"
[ ! -s "$CALLS" ]
[ "$(grep -c -- '--security-audit' "$WORK/out")" -eq 2 ]
echo 'OK: Sicherheitslauf über Projektliste'
