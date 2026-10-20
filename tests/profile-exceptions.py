#!/usr/bin/env python3
"""Netzwerkfreie Selbsttests der projektbezogenen Check-Ausnahmen."""
import contextlib
import importlib.machinery
import io
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "claude/skills/code-quality/bin"
CHECK = sys.argv[1]


def load(name):
    return importlib.machinery.SourceFileLoader(name.replace('-', '_'), str(BIN / name)).load_module()


def profile(directory, entries, art=None):
    folder = directory / ".ai"
    folder.mkdir(exist_ok=True)
    (folder / "guard-profile.yml").write_text(yaml.safe_dump({"projekt_art": art, "ausnahmen": entries}, allow_unicode=True), encoding="utf-8")


def captured(func):
    stream = io.StringIO()
    with contextlib.redirect_stdout(stream):
        result = func()
    return result, stream.getvalue()


def run_web(name, key, path, message):
    from guard_profile import Profile
    module = load(name)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        entry = {"check": name.removeprefix("check-"), "befund": key, "pfad": path, "grund": "Geprüfte Ausnahme"}
        profile(root, [entry])
        module.profile = Profile(root, entry["check"])
        _, out = captured(lambda: module.finding(message, key, path))
        assert "bewusst ausgenommen" in out and "BEFUND" not in out, out
        entry.pop("grund")
        profile(root, [entry])
        module.profile = Profile(root, entry["check"])
        _, out = captured(lambda: module.profile.initial())
        assert "Ausnahme ohne Begründung" in out, out
        entry["grund"] = "Vergangene Ausnahme"
        entry["ablaufdatum"] = "2000-01-01"
        profile(root, [entry])
        module.profile = Profile(root, entry["check"])
        _, out = captured(lambda: module.finding(message, key, path))
        assert "Ausnahme abgelaufen seit" in out and "BEFUND" in out, out
        entry.pop("ablaufdatum")
        entry["nur_umgebung"] = "dev"
        profile(root, [entry])
        module.profile = Profile(root, entry["check"])
        module.page_dev = False if hasattr(module, "page_dev") else None
        module.dev_mode = False if hasattr(module, "dev_mode") else None
        _, out = captured(lambda: module.finding(message, key, path))
        assert "BEFUND" in out, out
        if hasattr(module, "page_dev"):
            module.page_dev = True
        if hasattr(module, "dev_mode"):
            module.dev_mode = True
        _, out = captured(lambda: module.finding(message, key, path))
        assert "bewusst ausgenommen" in out, out
    return module


sys.path.insert(0, str(BIN / "lib"))
from guard_profile import Profile, is_dev
assert is_dev([("X-Debug-Token", "abc")])
assert is_dev(body="<div class='sf-toolbar'>Debug</div>")
assert not is_dev(body="<main>Produktion</main>")
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    profile(root, [{"check": CHECK, "befund": "probe", "muster": "/hilfe/*",
                    "grund": "Dokumentation"}])
    probe = Profile(root, CHECK)
    assert probe.decide("probe", "/hilfe/seite")[0] == "Dokumentation"
    assert probe.decide("probe", "/kontakt")[0] is None
    profile(root, [{"check": CHECK, "befund": "probe", "grund": "Global"}])
    assert Profile(root, CHECK).decide("probe", "/beliebig")[0] == "Global"
if CHECK == "form-protection":
    m = run_web("check-form-protection", "honeypot", "/dev-login", "/dev-login: Formular ohne Honeypot")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        entry = {"check": "form-protection", "befund": "honeypot", "pfad": "/dev-login",
                 "nur_umgebung": "dev", "grund": "Lokales Entwicklungsformular"}
        profile(root, [entry])
        from guard_profile import Profile
        m.profile = Profile(root, "form-protection")
        form = m.FormParser()
        form.feed('<html><body><form method="post" action="/dev-login">'
                  '<input type="email" name="email"><textarea name="text"></textarea>'
                  '</form></body></html>')
        m.page_dev = True
        _, out = captured(lambda: m.check_forms("/dev-login", form))
        assert "bewusst ausgenommen" in out and "BEFUND" not in out, out
        m.page_dev = False
        _, out = captured(lambda: m.check_forms("/dev-login", form))
        assert "BEFUND" in out, out
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        profile(root, [], "intern")
        from guard_profile import Profile
        m.profile = Profile(root, "form-protection")
        _, out = captured(lambda: m.finding("/kontakt: Formular ohne Honeypot", "honeypot", "/kontakt"))
        assert "entfällt bei projekt_art: intern" in out and "BEFUND" not in out, out
        login = m.FormParser()
        login.feed('<html><body><form method="post" action="/login">'
                   '<input name="user"><input type="password" name="password">'
                   '</form></body></html>')
        _, out = captured(lambda: m.check_forms("/login", login))
        assert "entfällt bei projekt_art: intern" in out and "BEFUND" not in out, out
elif CHECK == "web-content":
    m = run_web("check-web-content", "canonical", "/hilfe", "/hilfe: canonical fehlt")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        profile(root, [], "intern")
        from guard_profile import Profile
        m.profile = Profile(root, "web-content")
        _, seo = captured(lambda: m.finding("/hilfe: canonical fehlt", "canonical", "/hilfe"))
        _, access = captured(lambda: m.finding("/hilfe: lang fehlt", "lang", "/hilfe"))
        assert "entfällt bei projekt_art: intern" in seo and "BEFUND" in access, (seo, access)
elif CHECK == "web-exposure":
    m = run_web("check-web-exposure", "cookie-flags", "/", "Cookie ohne SameSite")
    m.request = lambda url: (404, [("X-Debug-Token", "abc")], b"Stack trace")
    _, out = captured(m.check_unknown_path)
    assert "nur im Dev-Modus" in out and "BEFUND" not in out, out
    m.request = lambda url: (404, [], b"Stack trace")
    _, out = captured(m.check_unknown_path)
    assert "[web-exposure/stacktrace] Fehlerseite zeigt einen Stacktrace" in out, out
elif CHECK == "gate-integrity":
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        def git(*args):
            subprocess.run(["git", "-C", str(root), *args], check=True, stdout=subprocess.DEVNULL)
        git("init", "-q", "-b", "main")
        git("config", "user.email", "test@example.invalid")
        git("config", "user.name", "Test")
        (root / "phpcs.xml").write_text("<ruleset></ruleset>")
        git("add", ".")
        git("commit", "-q", "-m", "Basis")
        git("checkout", "-q", "-b", "feature")
        (root / "phpcs.xml").write_text("<ruleset><exclude-pattern>config/reference.php</exclude-pattern></ruleset>")
        entry = {"check": "gate-integrity", "befund": "G3", "pfad": "config/reference.php", "grund": "Generierte Symfony-Referenz"}
        def check():
            return subprocess.run([str(BIN / "check-gate-integrity"), str(root), "main"], capture_output=True, text=True)
        profile(root, [entry])
        result = check()
        assert result.returncode == 0 and "bewusst ausgenommen" in result.stdout, result.stdout
        del entry["grund"]
        profile(root, [entry])
        result = check()
        assert result.returncode == 1 and "Ausnahme ohne Begründung" in result.stdout, result.stdout
        entry["grund"] = "Zu alt"
        entry["ablaufdatum"] = "2000-01-01"
        profile(root, [entry])
        result = check()
        assert result.returncode == 1 and "Ausnahme abgelaufen seit" in result.stdout, result.stdout
else:
    raise SystemExit(f"Unbekannter Check: {CHECK}")
print("OK: Profil-Ausnahmen")
