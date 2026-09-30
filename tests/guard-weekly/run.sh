#!/usr/bin/env bash
#
# Selbsttest für guard-weekly: Branch-Abgleich (nur Fast-Forward) und Todo-Modus.
#
# Jeder Fall baut zur Laufzeit ein nacktes origin plus Klon in einem
# mktemp-Verzeichnis. code-guard wird über GUARD_WEEKLY_CODE_GUARD durch einen
# Stub ersetzt, der ein results.json mit einem FAIL-Check schreibt; der Agent
# ist `none`. Vikunja ist ein kleiner python3-Stub auf 127.0.0.1, der die
# Anfragen protokolliert. Am Ende:
#   OK: alle Fälle bestanden   (Exit 0)
# sonst eine Meldung und Exit 1.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$BASE_DIR/claude/skills/code-quality/bin/guard-weekly"

if [ ! -x "$SCRIPT" ]; then
    echo "FEHLER: Script nicht gefunden oder nicht ausführbar: $SCRIPT" >&2
    exit 1
fi

WORK="$(mktemp -d)"
STUB_PID=""
cleanup() {
    [ -z "$STUB_PID" ] || kill "$STUB_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.org
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail=0
RC=0
OUT=""

# --------------------------------------------------------------- Stubs -------

cat > "$WORK/code-guard-stub" <<'STUB'
#!/usr/bin/env bash
project=""
while [ $# -gt 0 ]; do
    case "$1" in --project) project="$2"; shift 2 ;; *) shift ;; esac
done
mkdir -p "$project/docs/.guard/logs"
printf 'Zeile 1\nPHPStan: 3 Fehler <b>kaputt</b>\n' > "$project/docs/.guard/logs/phpstan.log"
cat > "$project/docs/.guard/results.json" <<'JSON'
{"verdict":"FAIL","checks":[
 {"id":"phpstan","label":"Statische Analyse","status":"PHPSTAN_STATUS","command":"make phpstan","log":"docs/.guard/logs/phpstan.log","note":""},
 {"id":"phpcs","label":"Code-Stil","status":"PASS","command":"make phpcs","log":"","note":""}
]}
JSON
sed -i "s/PHPSTAN_STATUS/${STUB_PHPSTAN:-FAIL}/" "$project/docs/.guard/results.json"
if [ -n "${STUB_SIDE_EFFECT:-}" ]; then
    echo "regeneriert" >> "$project/file.txt"
    exit 3
fi
exit 1
STUB
chmod +x "$WORK/code-guard-stub"
export GUARD_WEEKLY_CODE_GUARD="$WORK/code-guard-stub"

cat > "$WORK/vikunja-stub.py" <<'PY'
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
log_path, port_path = sys.argv[1], sys.argv[2]
tasks = []
seed_path = sys.argv[3] if len(sys.argv) > 3 else ""
def load_seed():
    if seed_path:
        try:
            lines = [l for l in open(seed_path) if l.strip()]
            if lines:
                tasks.clear()   # ein Seed ersetzt den Zustand frueherer Faelle
            for line in lines:
                if line.strip():
                    tid, title = line.rstrip("\n").split("\t", 1)
                    tasks.append({"id": int(tid), "title": title, "done": False})
            open(seed_path, "w").close()
        except FileNotFoundError:
            pass
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def _log(self, body=""):
        with open(log_path, "a") as f:
            f.write(f"{self.command} {self.path} {body}\n")
    def do_GET(self):
        self._log()
        if self.headers.get("Authorization") != "Bearer testtoken":
            return self._send(401, {"message": "unauthorized"})
        load_seed()
        path = urllib.parse.urlparse(self.path).path
        if path.startswith("/tasks/"):
            t = next((t for t in tasks if t["id"] == int(path.split("/")[2])), None)
            return self._send(200, dict(t, description="alt", priority=3)) if t else self._send(404, {})
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        page = int(q.get("page", ["1"])[0])
        self._send(200, [t for t in tasks if not t["done"]] if page == 1 else [])
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        self._log(body)
        data = json.loads(body)
        t = next((t for t in tasks if t["id"] == int(self.path.split("/")[2])), None)
        if t is None or data.get("description") != "alt" or data.get("priority") != 3:
            return self._send(400, {"message": "Datensatz unvollstaendig"})
        t["done"] = bool(data.get("done"))
        self._send(200, dict(t, description="alt", priority=3))
    def do_PUT(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        self._log(body)
        data = json.loads(body)
        if self.path.endswith("/comments"):
            return self._send(201, {"id": 1, "comment": data["comment"]})
        t = {"id": len(tasks) + 100, "title": data["title"], "done": False}
        tasks.append(t); self._send(201, t)
s = HTTPServer(("127.0.0.1", 0), H)
open(port_path, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
python3 "$WORK/vikunja-stub.py" "$WORK/vikunja.log" "$WORK/vikunja.port" "$WORK/vikunja.seed" &
STUB_PID=$!
for _ in $(seq 50); do [ -s "$WORK/vikunja.port" ] && break; sleep 0.1; done
VIKUNJA_URL="http://127.0.0.1:$(cat "$WORK/vikunja.port")"

# ------------------------------------------------------------- Helfer --------

# new_repo -> legt origin (bare) + Klon an, main mit einem Commit; gibt Klonpfad aus.
# Läuft in $(...), deshalb ein eigenes mktemp-Verzeichnis statt eines Zählers.
new_repo() {
    local d; d="$(mktemp -d "$WORK/case.XXXX")"
    git init -q --bare -b main "$d/origin.git"
    git clone -q "$d/origin.git" "$d/clone" 2>/dev/null
    (
        cd "$d/clone"
        git checkout -q -b main 2>/dev/null || true
        echo "a" > file.txt
        printf 'docs/.guard/\n' > .gitignore
        git add . && git commit -q -m init && git push -q origin main
    ) >/dev/null 2>&1
    echo "$d/clone"
}

run_weekly() {
    local dir="$1"; shift
    if OUT="$(cd "$dir" && HOME="$WORK/home" "$SCRIPT" --project "$dir" --agent none --no-push "$@" 2>&1)"; then
        RC=0
    else
        RC=$?
    fi
}

expect() {
    local name="$1" cond="$2"
    if eval "$cond"; then
        echo "  ok   $name"
    else
        echo "  FAIL $name  (Exit $RC)"; printf '%s\n' "$OUT" | sed 's/^/       /'
        fail=1
    fi
}

clean() { [ -z "$(git -C "$1" status --porcelain)" ]; }

mkdir -p "$WORK/home"

# ------------------------------------------------------------- Fälle ---------

echo "a) develop fehlt -> aus main angelegt"
R="$(new_repo)"
run_weekly "$R" --no-commit
expect "Exit 0" '[ "$RC" -eq 0 ]'
expect "develop existiert" 'git -C "$R" show-ref --verify --quiet refs/heads/develop'
expect "Meldung angelegt" 'grep -q "aus origin/main angelegt" <<<"$OUT"'

echo "c) main und develop auseinandergelaufen -> Exit 12, Branch-Abgleich bleibt Sache des Aufrufers"
R="$(new_repo)"
(
    cd "$R"
    git checkout -q -b develop && echo dev > file.txt && git commit -q -am dev && git push -q origin develop
    git checkout -q main && echo main > file.txt && git commit -q -am main && git push -q origin main
    git checkout -q develop
)
run_weekly "$R" --no-commit
expect "Exit 12" '[ "$RC" -eq 12 ]'
expect "kein MERGE_HEAD" '[ ! -e "$R/.git/MERGE_HEAD" ]'
expect "Worktree sauber" 'clean "$R"'

echo "e) lokaler develop mit eigener Arbeit, divergent -> Exit 12, Arbeit bleibt"
R="$(new_repo)"
(
    cd "$R"
    git checkout -q -b develop && git push -q origin develop
    echo lokal > lokal.txt && git add lokal.txt && git commit -q -m lokal
    git clone -q "$(dirname "$R")/origin.git" "$(dirname "$R")/other" 2>/dev/null
    cd "$(dirname "$R")/other" && git checkout -q develop && echo c > c.txt && git add c.txt && git commit -q -m c && git push -q origin develop
)
LOCAL_SHA="$(git -C "$R" rev-parse develop)"
run_weekly "$R" --no-commit
expect "Exit 12" '[ "$RC" -eq 12 ]'
expect "lokaler Commit noch da" '[ "$(git -C "$R" rev-parse develop)" = "$LOCAL_SHA" ]'

echo "f) Todo-Modus: Task anlegen, beim zweiten Lauf nur kommentieren"
R="$(new_repo)"
: > "$WORK/vikunja.log"
export VIKUNJA_BASE_URL="$VIKUNJA_URL" VIKUNJA_API_TOKEN=testtoken
run_weekly "$R" --vikunja-project 81
expect "Exit 0" '[ "$RC" -eq 0 ]'
expect "1 angelegt" 'grep -q "1 Tasks angelegt, 0 kommentiert" <<<"$OUT"'
expect "Titel ohne Status" 'grep -q "\"title\": \"\[Guard\] clone: Statische Analyse (phpstan)\"" "$WORK/vikunja.log"'
expect "PASS-Check kein Task" '! grep -q "Code-Stil" "$WORK/vikunja.log"'
expect "Log-Inhalt escaped" 'grep -q "&lt;b&gt;kaputt" "$WORK/vikunja.log"'
expect "an Projekt 81" 'grep -q "^PUT /projects/81/tasks" "$WORK/vikunja.log"'
expect "Worktree sauber" 'clean "$R"'
run_weekly "$R" --vikunja-project 81
expect "zweiter Lauf Exit 0" '[ "$RC" -eq 0 ]'
expect "0 angelegt, 1 kommentiert" 'grep -q "0 Tasks angelegt, 1 kommentiert" <<<"$OUT"'
expect "Kommentar an Task 100" 'grep -q "^PUT /tasks/100/comments" "$WORK/vikunja.log"'
expect "Worktree weiter sauber" 'clean "$R"'
run_weekly "$R" --vikunja-project 81
STUB_PHPSTAN=PASS run_weekly "$R" --vikunja-project 81
expect "PASS -> geschlossen" 'grep -q "0 Tasks angelegt, 0 kommentiert, 1 geschlossen" <<<"$OUT"'
expect "Behoben-Kommentar" 'grep -q "Automatisch geschlossen" "$WORK/vikunja.log"'
expect "done gesetzt, Datensatz vollstaendig" 'grep -q "^POST /tasks/100 .*\"done\":true" "$WORK/vikunja.log"'
STUB_PHPSTAN=FAIL run_weekly "$R" --vikunja-project 81
expect "danach neuer Task" 'grep -q "1 Tasks angelegt, 0 kommentiert, 0 geschlossen" <<<"$OUT"'
unset VIKUNJA_BASE_URL VIKUNJA_API_TOKEN

echo "f2) alter Titel mit Status wird über die Check-ID erkannt"
R="$(new_repo)"
: > "$WORK/vikunja.log"
printf '500\t[Guard] clone: Statische Analyse (phpstan) MISSING\n501\t[Guard] anderes: Statische Analyse (phpstan) FAIL\n' > "$WORK/vikunja.seed"
export VIKUNJA_BASE_URL="$VIKUNJA_URL" VIKUNJA_API_TOKEN=testtoken
run_weekly "$R" --vikunja-project 81
expect "kommentiert statt neu" 'grep -q "0 Tasks angelegt, 1 kommentiert" <<<"$OUT"'
expect "an Task 500" 'grep -q "^PUT /tasks/500/comments" "$WORK/vikunja.log"'
expect "fremdes Projekt unberührt" '! grep -q "/tasks/501" "$WORK/vikunja.log"'
unset VIKUNJA_BASE_URL VIKUNJA_API_TOKEN

echo "g) Todo-Modus ohne Zugangsdaten -> Exit 16"
R="$(new_repo)"
run_weekly "$R" --vikunja-project 81
expect "Exit 16" '[ "$RC" -eq 16 ]'
expect "Worktree sauber" 'clean "$R"'

echo "h) Todo-Modus mit falschem Token -> Exit 16"
R="$(new_repo)"
export VIKUNJA_BASE_URL="$VIKUNJA_URL" VIKUNJA_API_TOKEN=falsch
run_weekly "$R" --vikunja-project 81
expect "Exit 16" '[ "$RC" -eq 16 ]'
unset VIKUNJA_BASE_URL VIKUNJA_API_TOKEN

echo "j) Todo-Modus mit Seiteneffekt -> Todo dafür, Datei zurückgesetzt"
R="$(new_repo)"
: > "$WORK/vikunja.log"
export VIKUNJA_BASE_URL="$VIKUNJA_URL" VIKUNJA_API_TOKEN=testtoken
STUB_SIDE_EFFECT=1 run_weekly "$R" --vikunja-project 81
expect "Exit 0" '[ "$RC" -eq 0 ]'
expect "Seiteneffekt-Task" 'grep -qF "Seiteneffekt im Worktree (side-effect)" "$WORK/vikunja.log"'
expect "Datei im Task genannt" 'grep -q "file.txt" "$WORK/vikunja.log"'
expect "Worktree sauber" 'clean "$R"'
run_weekly "$R" --vikunja-project 81
expect "Seiteneffekt weg -> Task geschlossen" 'grep -q "Geschlossen: #.* (side-effect)" <<<"$OUT"'
unset VIKUNJA_BASE_URL VIKUNJA_API_TOKEN

echo "k) Seiteneffekt ohne Todo-Modus -> weiterhin Exit 15"
R="$(new_repo)"
STUB_SIDE_EFFECT=1 run_weekly "$R" --no-commit
expect "Exit 15" '[ "$RC" -eq 15 ]'

echo "i) ungültige Projekt-ID -> Exit 2"
R="$(new_repo)"
run_weekly "$R" --vikunja-project abc
expect "Exit 2" '[ "$RC" -eq 2 ]'

if [ "$fail" -eq 0 ]; then
    echo "OK: alle Fälle bestanden"
    exit 0
fi
echo "FEHLER: mindestens ein Fall ist fehlgeschlagen" >&2
exit 1
