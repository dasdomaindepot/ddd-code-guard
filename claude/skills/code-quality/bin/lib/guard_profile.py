"""Gemeinsames Projektprofil für deterministische Checks."""

from datetime import date
from fnmatch import fnmatchcase
from pathlib import Path
import re


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
        self.exceptions = []
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
