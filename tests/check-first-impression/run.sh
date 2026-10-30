#!/usr/bin/env bash
# Selbsttest für check-first-impression mit lokaler Vision-API und fertigen PNGs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../claude/skills/code-quality/bin/check-first-impression"
TMP="$(mktemp -d)"
trap 'kill "${SERVER_PID:-}" 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/project/.ai" "$TMP/shots" "$TMP/config"
python3 - "$TMP/shots" <<'PY'
from pathlib import Path
import base64, sys
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=')
for name in ('desktop', 'mobil'):
    (Path(sys.argv[1]) / f'{name}.png').write_bytes(png)
PY
cat > "$TMP/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        req = json.loads(self.rfile.read(length))
        assert self.path == '/v1/chat/completions'
        assert req['chat_template_kwargs'] == {'enable_thinking': False}
        assert req['temperature'] == 0.2
        content = req['messages'][0]['content']
        mode = open(os.environ['MODE_FILE']).read().strip()
        if isinstance(content, list):
            assert any(c.get('type') == 'image_url' and c['image_url']['url'].startswith('data:image/') for c in content)
            result = {'angebot': 'Handgemachte Waren', 'zielgruppe': 'Käufer', 'naechster_schritt': 'Zum Katalog', 'sicherheit': 55 if mode == 'low' else 95, 'was_fehlt': ''}
        else:
            result = {'passt': 'nein' if mode == 'mismatch' else 'ja', 'begruendung': 'Klar erkennbar', 'vorschlag_headline': 'Handgemachte Waren', 'vorschlag_subline': 'Für Käufer', 'vorschlag_cta': 'Zum Katalog'}
        value = json.dumps(result)
        if mode == 'fence': value = '```json\n' + value + '\n```'
        body = json.dumps({'choices': [{'message': {'content': value}}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass
HTTPServer(('127.0.0.1', int(os.environ['PORT'])), Handler).serve_forever()
PY
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
MODE_FILE="$TMP/mode" PORT="$PORT" python3 "$TMP/server.py" & SERVER_PID=$!
for _ in $(seq 1 50); do
    if python3 - "$PORT" <<'PY'
import socket, sys
s = socket.socket(); s.settimeout(.1); code = s.connect_ex(('127.0.0.1', int(sys.argv[1]))); s.close(); sys.exit(code)
PY
    then break; fi
    sleep .1
done
printf 'angebot: Handgemachte Waren für Käufer.\n' > "$TMP/project/.ai/guard-profile.yml"
export XDG_CONFIG_HOME="$TMP/config" GUARD_FIRST_IMPRESSION_SCREENSHOTS="$TMP/shots"
export GUARD_VISION_URL="http://127.0.0.1:$PORT/v1" GUARD_VISION_MODEL='testmodell' GUARD_VISION_KEY='test'
run_case() {
    local expected="$1" mode="$2" needle="$3" rc=0 out
    printf '%s' "$mode" > "$TMP/mode"
    out="$("$SCRIPT" 'http://127.0.0.1:1' "$TMP/project" 2>&1)" || rc=$?
    if [ "$rc" -ne "$expected" ] || [[ "$out" != *"$needle"* ]]; then
        echo "FEHLER: $mode: Exit $rc statt $expected oder Text fehlt: $needle" >&2
        echo "$out" >&2
        exit 1
    fi
}
run_case 0 clear 'Keine Befunde'
run_case 1 low 'BEFUND'
run_case 1 mismatch 'passt nicht'
run_case 0 fence 'Keine Befunde'
printf 'projekt_art: web\n' > "$TMP/project/.ai/guard-profile.yml"
run_case 0 clear 'angebot:'
run_case 1 low 'BEFUND'
unset GUARD_VISION_URL GUARD_VISION_MODEL GUARD_VISION_KEY
run_case 77 clear 'GUARD_VISION_URL'
printf 'projekt_art: intern\n' > "$TMP/project/.ai/guard-profile.yml"
run_case 0 clear 'abgeschaltet'
printf 'checks_aus:\n  - check: first-impression\n    grund: bewusst ausgesetzt\n' > "$TMP/project/.ai/guard-profile.yml"
run_case 0 clear 'abgeschaltet'
echo 'OK: alle Fälle bestanden'
