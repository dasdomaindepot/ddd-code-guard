#!/usr/bin/env python3
"""Erzeugt Fixture-Seiten für den Selbsttest von check-web-resources.

Aufruf:  make_fixtures.py <zielverzeichnis>

Legt unter <zielverzeichnis> je Prüfall einen Unterordner an (gut, kaputt, hinweise,
toolbar) mit einer index.html und den zugehörigen Bilddateien. Die Bilder werden zur
Laufzeit erzeugt und nicht im Repo gespeichert.
"""

import os
import struct
import sys
import zlib


def png_chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data +
            struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))


def make_png(width, height, rgb=(10, 30, 60), level=9):
    """Minimales PNG, Farbtyp 2 (RGB), 8 Bit, eine Farbe.
    level=0 liefert ein unkomprimiertes IDAT und damit ein großes (über 300 KB) PNG."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = bytearray()
    for _ in range(height):
        raw.append(0)  # Filterart keine
        raw.extend(rgb * width)
    body = png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(raw), level))
    return signature + body + png_chunk(b"IEND", b"")


def write_bytes(path, data):
    with open(path, "wb") as f:
        f.write(data)


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


INDEX = '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>{title}</title>
{head}
</head>
<body>
<h1>{title}</h1>
<p>{text}</p>
{body}
</body>
</html>
'''


def index_html(title, head, text, body=""):
    return INDEX.format(title=title, head=head, text=text, body=body)


def build_gut(d):
    write_png(os.path.join(d, "logo.png"), 50, 50)
    head = '<link rel="icon" href="/logo.png">'
    body = """<a href="/kontakt/">Zum Kontakt</a>
<a href="mailto:test@example.com">E-Mail</a>
<a href="#top">Nach oben</a>
<a href="/logout">Abmelden</a>
<img src="/logo.png" width="50" height="50" alt="Logo">
<script src="https://cdn.example.com/x.js" integrity="sha384-example-defer" defer></script>"""
    write_text(os.path.join(d, "index.html"),
               index_html("gut", head, "Alle Ressourcen in Ordnung.", body))
    kontakt = os.path.join(d, "kontakt")
    os.makedirs(kontakt, exist_ok=True)
    write_text(os.path.join(kontakt, "index.html"),
                index_html("kontakt", "", "Kontaktseite",
                           '<a href="/">Zurück zur Startseite</a>'))


def build_kaputt(d):
    head = ""
    body = """<a href="/gibt-es-nicht">Fehlende Seite</a>
<img src="/fehlt.png" width="10" height="10" alt="fehlt">"""
    write_text(os.path.join(d, "index.html"),
                index_html("kaputt", head, "Ein kaputter Link und ein kaputter Bild.", body))
    write_text(os.path.join(d, "unter.html"),
                index_html("unter", "", "Unterseite",
                           '<a href="/gibt-es-nicht">Fehlende Seite</a>'))
    write_text(os.path.join(d, "sitemap.xml"),
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
                '<url><loc>/</loc></url>'
                '<url><loc>/unter.html</loc></url>'
                '</urlset>')


def build_hinweise(d):
    write_png(os.path.join(d, "grosse.png"), 400, 400, level=0)
    head = ""
    body = """<a href="/umweg1">Über den Umweg</a>
<a href="/kontakt/">Kontakt</a>
<img src="/grosse.png" width="400" alt="Großes Bild ohne Höhe">
<script src="https://cdn.example.com/x.js"></script>"""
    write_text(os.path.join(d, "index.html"),
               index_html("hinweise", head, "Nur Hinweise.", body))
    kontakt = os.path.join(d, "kontakt")
    os.makedirs(kontakt, exist_ok=True)
    write_text(os.path.join(kontakt, "index.html"),
                index_html("kontakt", "", "Kontaktseite existiert."))


def build_toolbar(d):
    body = ('<div id="sfwdt1" class="sf-toolbar">'
            '<a href="/_kaputt">x</a>'
            '<img src="/nix.png">'
            '</div>')
    write_text(os.path.join(d, "index.html"),
               index_html("toolbar", "", "Die Symfony-Toolbar wird ignoriert.", body))


FÄLLE = {
    "gut": build_gut,
    "kaputt": build_kaputt,
    "hinweise": build_hinweise,
    "toolbar": build_toolbar,
}


def write_png(path, width, height, level=9):
    write_bytes(path, make_png(width, height, level=level))


def main() -> int:
    if len(sys.argv) != 2:
        print("Verwendung: make_fixtures.py <zielverzeichnis>", file=sys.stderr)
        return 2
    ziel = sys.argv[1]
    os.makedirs(ziel, exist_ok=True)
    for name, build in FÄLLE.items():
        ordner = os.path.join(ziel, name)
        os.makedirs(ordner, exist_ok=True)
        build(ordner)
        print(f"erzeugt: {ordner}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
