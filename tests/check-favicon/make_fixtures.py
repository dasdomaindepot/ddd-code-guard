#!/usr/bin/env python3
"""Erzeugt Fixture-Seiten für den Selbsttest von check-favicon.

Aufruf:  make_fixtures.py <zielverzeichnis>

Legt unter <zielverzeichnis> je Prüfall einen Unterordner an (komplett,
nichts, falsch, ohne-extras, kaputtes-manifest) mit einer index.html und den
zugehörigen Bilddateien. Die Bilder werden zur Laufzeit erzeugt und nicht im
Repo gespeichert.
"""

import json
import os
import struct
import sys
import zlib


def png_chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data +
            struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))


def make_png(width, height, rgb=(10, 30, 60)):
    """Minimales PNG, Farbtyp 2 (RGB), 8 Bit, eine Farbe."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = bytearray()
    for _ in range(height):
        raw.append(0)  # Filterart keine
        raw.extend(rgb * width)
    body = png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    return signature + body + png_chunk(b"IEND", b"")


def make_ico(entries):
    """ICO mit eingebetteten PNGs. entries: Liste (sichtbare_breite, sichtbare_hoehe, png)."""
    header = b"\x00\x00\x01\x00" + struct.pack("<H", len(entries))
    dir_entries = bytearray()
    bitmap = bytearray()
    offset = 6 + len(entries) * 16
    for dw, dh, png in entries:
        w = 0 if dw >= 256 else dw
        h = 0 if dh >= 256 else dh
        dir_entries += bytes([w, h, 0, 0]) + struct.pack("<HH", 1, 32)
        dir_entries += struct.pack("<II", len(png), offset)
        bitmap += png
        offset += len(png)
    return header + bytes(dir_entries) + bytes(bitmap)


def write_bytes(path, data):
    with open(path, "wb") as f:
        f.write(data)


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def make_ico_file(path, breiten_hoehen):
    entries = [(b, h, make_png(b, h)) for b, h in breiten_hoehen]
    write_bytes(path, make_ico(entries))


def make_png_file(path, width, height, rgb=(10, 30, 60)):
    write_bytes(path, make_png(width, height, rgb))


SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">\n' \
      '<rect width="32" height="32" rx="4" fill="#0a1e3b"/>\n' \
      '<circle cx="16" cy="16" r="8" fill="#f26419"/>\n</svg>\n'


INDEX = '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>{title}</title>
{links}
</head>
<body>
<h1>{title}</h1>
<p>{text}</p>
</body>
</html>
'''


def index_html(title, links, text):
    return INDEX.format(title=title, links=links, text=text)


def manifest_json(icons):
    return json.dumps({"name": "Test-App", "icons": icons}, ensure_ascii=False, indent=2) + "\n"


def build_komplett(d):
    make_ico_file(os.path.join(d, "favicon.ico"), [(16, 16), (32, 32)])
    make_png_file(os.path.join(d, "apple-touch-icon.png"), 180, 180)
    make_png_file(os.path.join(d, "icon-192.png"), 192, 192)
    make_png_file(os.path.join(d, "icon-512.png"), 512, 512, rgb=(240, 100, 20))
    make_png_file(os.path.join(d, "icon-mask.png"), 512, 512, rgb=(240, 100, 20))
    write_text(os.path.join(d, "icon.svg"), SVG)
    write_text(os.path.join(d, "manifest.webmanifest"), manifest_json([
        {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
        {"src": "/icon-mask.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ]))
    links = """<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">"""
    write_text(os.path.join(d, "index.html"),
               index_html("Komplett", links, "Alle Favicon-Links vorhanden und korrekt."))


def build_nichts(d):
    write_text(os.path.join(d, "index.html"),
               index_html("Nichts", "", "Keine Favicon-Dateien oder Links."))


def build_falsch(d):
    make_ico_file(os.path.join(d, "favicon.ico"), [(16, 16), (32, 32)])
    make_png_file(os.path.join(d, "icon-32.png"), 64, 64)
    make_png_file(os.path.join(d, "apple-touch-icon.png"), 57, 57)
    make_png_file(os.path.join(d, "icon-192.png"), 192, 192)
    write_text(os.path.join(d, "manifest.webmanifest"), manifest_json([
        {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
    ]))
    links = """<link rel="icon" href="/icon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/weg.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">"""
    write_text(os.path.join(d, "index.html"),
               index_html("Falsch", links, "Viele Kleinigkeiten falsch."))


def build_ohne_extras(d):
    make_ico_file(os.path.join(d, "favicon.ico"), [(16, 16)])
    make_png_file(os.path.join(d, "icon.png"), 32, 32)
    make_png_file(os.path.join(d, "apple-touch-icon.png"), 180, 180)
    make_png_file(os.path.join(d, "icon-192.png"), 192, 192)
    make_png_file(os.path.join(d, "icon-512.png"), 512, 512, rgb=(240, 100, 20))
    write_text(os.path.join(d, "manifest.webmanifest"), manifest_json([
        {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
    ]))
    links = """<link rel="icon" href="/icon.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">"""
    write_text(os.path.join(d, "index.html"),
               index_html("Ohne Extras", links, "Ohne SVG- und maskable-Icon."))


def build_kaputtes_manifest(d):
    make_ico_file(os.path.join(d, "favicon.ico"), [(16, 16), (32, 32)])
    make_png_file(os.path.join(d, "apple-touch-icon.png"), 180, 180)
    make_png_file(os.path.join(d, "icon-192.png"), 192, 192)
    make_png_file(os.path.join(d, "icon-512.png"), 512, 512, rgb=(240, 100, 20))
    make_png_file(os.path.join(d, "icon-mask.png"), 512, 512, rgb=(240, 100, 20))
    write_text(os.path.join(d, "icon.svg"), SVG)
    write_text(os.path.join(d, "manifest.webmanifest"), "{kein json")
    links = """<link rel="icon" type="image/svg+xml" href="/icon.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">"""
    write_text(os.path.join(d, "index.html"),
               index_html("Kaputtes Manifest", links, "Das Manifest ist kein gültiges JSON."))


def build_inline_svg(d):
    """Wie komplett, aber das SVG-Icon steht als data:-URI direkt im HTML."""
    build_komplett(d)
    os.remove(os.path.join(d, "icon.svg"))
    links = """<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22><rect width=%2232%22 height=%2232%22/></svg>">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">"""
    write_text(os.path.join(d, "index.html"),
               index_html("Inline-SVG", links, "Das SVG-Icon steht als data:-URI im HTML."))


FÄLLE = {
    "inline-svg": build_inline_svg,
    "komplett": build_komplett,
    "nichts": build_nichts,
    "falsch": build_falsch,
    "ohne-extras": build_ohne_extras,
    "kaputtes-manifest": build_kaputtes_manifest,
}


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
