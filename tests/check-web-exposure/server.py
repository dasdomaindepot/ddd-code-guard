#!/usr/bin/env python3
"""Kleiner Testserver für check-web-exposure.

Aufruf: server.py <port> <fall>

Startet einen http.server.ThreadingHTTPServer auf 127.0.0.1, der je nach <fall>
verschieden antwortet. Fälle: sauber, leck, spa, debug, cookies, cors.
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
FALL = sys.argv[2] if len(sys.argv) > 2 else ""

HTML = b"<!doctype html><html><head><title>Test</title></head><body>Willkommen</body></html>"
STACK = b"Stack trace: #0 vendor/symfony/src/Controller/DefaultController.php"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def respond(self, status, body=b"", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or []):
            self.send_header(k, v)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]

        if FALL == "sauber":
            if path == "/":
                self.respond(200, HTML, [("Set-Cookie", "PHPSESSID=abc; Path=/; HttpOnly; SameSite=Lax")])
            else:
                self.respond(404, b"Not Found")
            return

        if FALL == "leck":
            if path == "/.env":
                self.respond(200, b"APP_SECRET=x")
            elif path == "/.git/HEAD":
                self.respond(200, b"ref: refs/heads/main")
            elif path == "/":
                self.respond(200, HTML)
            else:
                self.respond(500, STACK)
            return

        if FALL == "debug":
            if path == "/.env":
                self.respond(200, b"APP_SECRET=x", [("X-Debug-Token", "abc")])
            elif path == "/.git/HEAD":
                self.respond(200, b"ref: refs/heads/main", [("X-Debug-Token", "abc")])
            elif path == "/":
                self.respond(200, HTML, [("X-Debug-Token", "abc")])
            else:
                self.respond(500, STACK, [("X-Debug-Token", "abc")])
            return

        if FALL == "spa":
            self.respond(200, HTML)
            return

        if FALL == "cookies":
            if path == "/":
                self.respond(200, HTML, [
                    ("Set-Cookie", "PHPSESSID=abc; Path=/"),
                    ("Set-Cookie", "main_deauth_profile_token=x; Path=/"),
                    ("Set-Cookie", "main_auth_profile_token=y; Path=/"),
                ])
            else:
                self.respond(404, b"Not Found")
            return

        if FALL == "cors":
            if path == "/":
                self.respond(200, HTML, [
                    ("Access-Control-Allow-Origin", "*"),
                    ("Access-Control-Allow-Credentials", "true"),
                ])
            else:
                self.respond(200, HTML)
            return

        self.respond(404, b"Not Found")


def main():
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
