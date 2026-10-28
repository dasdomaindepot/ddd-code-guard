#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "claude/skills/code-quality/bin"
sys.path.insert(0, str(BIN / "lib"))
from guard_profile import Profile

with tempfile.TemporaryDirectory() as tmp:
    project = Path(tmp)
    (project / ".ai").mkdir()
    (project / ".ai/guard-profile.yml").write_text("""version: 1
projekt_art: intern
checks_aus:
  - check: app-static
    grund: Projektentscheidung.
  - check: phpcs
  - check: migrations
    grund: Altstand.
    ablaufdatum: 2000-01-01
  - check: unbekannt
    grund: Tippfehler.
dateien_aus:
  - muster: public/legacy/**
    grund: Fremdcode.
  - pfad: src/Generated/
    grund: Generiert.
  - muster: src/*.php
""", encoding="utf-8")
    profile = Profile(project, "app-static")
    assert profile.disabled_checks()["app-static"] == "Projektentscheidung."
    assert profile.disabled_checks()["apple-design"].startswith("projekt_art: intern")
    assert "phpcs" not in profile.disabled_checks()
    assert "migrations" not in profile.disabled_checks()
    assert profile.file_excluded("public/legacy/deep/a.css") == "Fremdcode."
    assert profile.file_excluded("src/Generated/Foo.php") == "Generiert."
    assert profile.file_excluded("src/Other.php") is None
    assert any("ohne Begründung" in p for p in profile.problems)
    assert any("abgelaufen seit" in h for h in profile.hints)
    assert any("unbekannter Check" in h for h in profile.hints)
    cli = subprocess.run([sys.executable, str(BIN / "lib/guard_profile.py"), "checks-aus", str(project)], capture_output=True, text=True)
    assert cli.returncode == 0 and "app-static\tProjektentscheidung." in cli.stdout
    assert "PROBLEM\t" in cli.stdout
    assert "HINWEIS\t" in cli.stdout

    (project / "Makefile").write_text("test:\n\t@true\n", encoding="utf-8")
    runner = BIN / "code-guard"
    result = subprocess.run([str(runner), "--project", str(project), "--only", "app-static", "--no-color"], capture_output=True, text=True)
    assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
    data = json.loads((project / "docs/.guard/results.json").read_text())
    assert any(c["id"] == "app-static" and c["status"] == "SKIPPED" and "Projektentscheidung." in c["note"] for c in data["checks"]), data
    assert any(c["id"] == "project-profile" and c["status"] == "FAIL" for c in data["checks"]), data
    listing = subprocess.run([str(runner), "--project", str(project), "--list", "--no-color"], capture_output=True, text=True)
    assert "abgeschaltet — Projektentscheidung." in listing.stdout, listing.stdout

print("OK: Projektprofil")


def git(project, *args):
    subprocess.run(["git", "-C", str(project), *args], check=True, capture_output=True)


def check(name, project, base=False):
    command = [str(BIN / f"check-{name}"), str(project)]
    if base:
        command.append("main")
    return subprocess.run(command, capture_output=True, text=True)


def excluded_case(name, files, needle, excluded, base=False):
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp)
        git(project, "init", "-q", "-b", "main")
        git(project, "config", "user.email", "test@example.invalid")
        git(project, "config", "user.name", "Test")
        (project / "README.md").write_text("Basis\n")
        git(project, "add", ".")
        git(project, "commit", "-q", "-m", "Basis")
        for path, body in files.items():
            target = project / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        if name == "secrets":
            git(project, "add", ".env.local")
        positive = check(name, project, base)
        assert needle in positive.stdout, (name, positive.stdout, positive.stderr)
        (project / ".ai").mkdir()
        (project / ".ai/guard-profile.yml").write_text(
            f"version: 1\ndateien_aus:\n  - pfad: {excluded}\n    grund: Testausschluss.\n", encoding="utf-8")
        negative = check(name, project, base)
        if name == "secrets":
            assert needle in negative.stdout, negative.stdout
        else:
            assert needle not in negative.stdout, (name, negative.stdout, negative.stderr)
            assert "1 Datei(en) per dateien_aus ausgenommen" in negative.stdout, (name, negative.stdout)


excluded_case("apple-design", {"public/legacy/a.html": "<p>Apple pay</p>"}, "Apple Pay falsch", "public/legacy/")
excluded_case("app-static", {"composer.json": "{}", "config/packages/framework.yaml": "framework:\n  session:\n    cookie_secure: false\n"}, "cookie_secure", "config/packages/framework.yaml")
excluded_case("house-rules", {"composer.json": "{}", ".env": "DB_PASSWORD=$SECRET\n"}, "DB_PASSWORD", ".env")
excluded_case("error-visibility", {"src/Controller/A.php": "<?php\nclass A { function run() { try {} catch (\\Exception $e) { echo $e; } } }\n"}, "catch gibt den Fehler direkt aus", "src/Controller/A.php", True)
excluded_case("migrations", {"migrations/Version123.php": "<?php\nuse App\\Entity\\User;\n"}, "Entities/Repositories", "migrations/Version123.php", True)
excluded_case("secrets", {".env.local": "APP_SECRET=secret\n"}, ".env.local ist versioniert", ".env.local", True)
print("OK: Dateiausschlüsse")
