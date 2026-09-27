#!/usr/bin/env python3
"""Kleiner lokaler Testserver für den Selbsttest von check-web-resources.

Aufruf:  server.py <port> <verzeichnis>

Liefert Dateien aus <verzeichnis> aus (SimpleHTTPRequestHandler mit directory=) und
antwortet zusätzlich für Weiterleitungsketten mit 302:
    /umweg1 -> /umweg2 -> /umweg3 -> /kontakt/
Dieser Server wird für alle Selbsttest-Fälle benutzt.
"""

import functools
import sys
from http.server import SimpleHTTPRequestHandler, HTTPServer

REDIRECTS = {
    "/umweg1": "/umweg2",
    "/umweg2": "/umweg3",
    "/umweg3": "/kontakt/",
}


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in REDIRECTS:
            self.send_response(302)
            self.send_header("Location", REDIRECTS[path])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        super().do_GET()

    def do_HEAD(self):
        path = self.path.split("?", 1)[0]
        if path in REDIRECTS:
            self.send_response(302)
            self.send_header("Location", REDIRECTS[path])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        super().do_HEAD()


def main() -> int:
    if len(sys.argv) != 3:
        print("Verwendung: server.py <port> <verzeichnis>", file=sys.stderr)
        return 2
    port = int(sys.argv[1])
    directory = sys.argv[2]
    handler = functools.partial(Handler, directory=directory)
    HTTPServer(("127.0.0.1", port), handler).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
