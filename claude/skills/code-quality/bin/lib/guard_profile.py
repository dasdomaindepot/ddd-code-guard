"""Gemeinsames Projektprofil für deterministische Checks."""

from datetime import date
from fnmatch import fnmatchcase
from pathlib import Path
import re
import os
import sys

KNOWN_CHECKS = set("composer-validate composer-audit versions npm-audit auth-policy app-static apple-design first-impression house-rules secrets symfony-lint gate-integrity error-visibility migrations phpcs phpstan deptrac lint npm-lint npm-typecheck npm-test test coverage infection e2e npm-build web-hardening legal web-exposure web-content form-protection favicon web-resources third-party browser-audit".split())


def is_dev(headers=(), body=""):
    """Lokale Symfony-Entwicklungsinstanz an Header oder Toolbar erkennen."""
    header_names = {str(k).lower() for k, _ in headers}
    return ("x-debug-token" in header_names or "x-debug-exception" in header_names
            or any(marker in body for marker in ('id="sfwdt', "id='sfwdt", 'id="sfToolbar',
                                                  "id='sfToolbar", 'class="sf-toolbar',
                                                  "class='sf-toolbar")))


class Profile:
    def __init__(self, project, check):
        self.check = check
        self.project_supplied = bool(project)
        self.art = None
        self.angebot = None
        self.exceptions = []
        self.checks_out = []
        self.files_out = []
        self.problems = []
        self.hints = []
        if not project:
            return
        file = Path(project) / ".ai" / "guard-profile.yml"
        if not file.is_file():
            return
        try:
            import yaml
        except ImportError:
            self.hints.append("PyYAML fehlt – .ai/guard-profile.yml nicht gelesen")
            return
        try:
            data = yaml.safe_load(file.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError):
            self.hints.append(".ai/guard-profile.yml nicht lesbar – Ausnahmen nicht berücksichtigt")
            return
        if not isinstance(data, dict):
            return
        self.art = data.get("projekt_art")
        self.angebot = data.get("angebot") if isinstance(data.get("angebot"), str) and data["angebot"].strip() else None
        for field, target in (("checks_aus", self.checks_out), ("dateien_aus", self.files_out)):
            for entry in data.get(field) or []:
                if not isinstance(entry, dict):
                    continue
                if not isinstance(entry.get("grund"), str) or not entry["grund"].strip():
                    self.problems.append(f"{field}-Eintrag ohne Begründung")
                    continue
                until = entry.get("ablaufdatum")
                if until:
                    try:
                        day = until if isinstance(until, date) else date.fromisoformat(str(until))
                    except ValueError:
                        self.hints.append(f"{field}-Eintrag mit ungültigem Ablaufdatum {until}")
                        continue
                    if day < date.today():
                        self.hints.append(f"{field}-Eintrag abgelaufen seit {day.isoformat()}")
                        continue
                if field == "checks_aus":
                    known = set(os.environ.get("GUARD_CHECK_IDS", "").split()) or KNOWN_CHECKS
                    if entry.get("check") not in known:
                        self.hints.append(f"unbekannter Check {entry.get('check')}")
                        continue
                elif not entry.get("pfad") and not entry.get("muster"):
                    self.hints.append("dateien_aus-Eintrag ohne pfad oder muster")
                    continue
                target.append(entry)
        for entry in data.get("ausnahmen") or []:
            if not isinstance(entry, dict) or entry.get("check") != check:
                continue
            if not isinstance(entry.get("grund"), str) or not entry["grund"].strip():
                self.problems.append(f"Ausnahme ohne Begründung ({check}/{entry.get('befund', '*')})")
                continue
            self.exceptions.append(entry)

    def initial(self):
        for message in self.hints:
            print(f"Hinweis  {message}")
        for message in self.problems:
            print(f"BEFUND   [{self.check}/ausnahme] {message}")
        return len(self.problems)

    def disabled_checks(self):
        result = {str(entry["check"]): entry["grund"].strip() for entry in self.checks_out}
        if self.art == "intern" and "apple-design" not in result:
            result["apple-design"] = "projekt_art: intern — kein Design-Anspruch"
        if self.art == "intern" and "first-impression" not in result:
            result["first-impression"] = "projekt_art: intern — kein öffentliches Angebot"
        return result

    def file_excluded(self, rel_path):
        rel_path = str(rel_path).replace("\\", "/")
        if rel_path.startswith("./"):
            rel_path = rel_path[2:]
        for entry in self.files_out:
            prefix = entry.get("pfad")
            pattern = entry.get("muster")
            if prefix and (rel_path == str(prefix).rstrip("/") or rel_path.startswith(str(prefix).rstrip("/") + "/")):
                return entry["grund"].strip()
            if pattern and fnmatchcase(rel_path, str(pattern)):
                return entry["grund"].strip()
        return None

    def decide(self, key, path, dev=False):
        """(Grund, Ablaufhinweise) für einen konkreten Befund."""
        expired = []
        for entry in self.exceptions:
            if entry.get("befund") and entry["befund"] != key:
                continue
            target = entry.get("pfad")
            pattern = entry.get("muster")
            if target and not (path == target or path.startswith(str(target).rstrip("/") + "/")):
                if self.check == "gate-integrity":
                    try:
                        re_match = re.search(path, str(target))
                    except re.error:
                        re_match = None
                    if re_match is None:
                        continue
                else:
                    continue
            if pattern and not fnmatchcase(path, str(pattern)):
                continue
            if entry.get("nur_umgebung") == "dev" and self.check != "gate-integrity" and not dev:
                continue
            until = entry.get("ablaufdatum")
            if until:
                try:
                    day = until if isinstance(until, date) else date.fromisoformat(str(until))
                except ValueError:
                    expired.append(f"Ausnahme mit ungültigem Ablaufdatum {until}")
                    continue
                if day < date.today():
                    expired.append(f"Ausnahme abgelaufen seit {day.isoformat()}")
                    continue
            return entry["grund"].strip(), expired
        return None, expired


class FileExclusions:
    """Pro Lauf ausgeschlossene Projektdateien zählen und einmal melden."""

    def __init__(self, project):
        self.project = Path(project).resolve()
        self.profile = Profile(project, "")
        self.skipped = set()

    def allowed(self, path):
        if not Path(path).is_file():
            return True
        try:
            rel = Path(path).absolute().relative_to(self.project).as_posix()
        except ValueError:
            return True
        if self.profile.file_excluded(rel):
            self.skipped.add(rel)
            return False
        return True

    def announce(self):
        if self.skipped:
            print(f"Hinweis  {len(self.skipped)} Datei(en) per dateien_aus ausgenommen")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "checks-aus":
        print("Verwendung: guard_profile.py checks-aus <projekt>", file=sys.stderr)
        sys.exit(2)
    profile = Profile(sys.argv[2], "")
    for check, reason in profile.disabled_checks().items():
        print(f"{check}\t{reason}")
    for message in profile.problems:
        print(f"PROBLEM\t{message}")
    for message in profile.hints:
        print(f"HINWEIS\t{message}")
