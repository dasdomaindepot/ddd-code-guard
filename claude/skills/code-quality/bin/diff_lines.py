"""Zeilenänderungen gegen den gemeinsamen Vorfahren eines Basis-Refs."""

import re
import subprocess


def git(project, *args):
    try:
        result = subprocess.run(["git", *args], cwd=project, capture_output=True,
                                text=True, encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return result.stdout if result.returncode == 0 else ""


def base_commit(project, ref):
    if not ref or not git(project, "rev-parse", "--verify", ref).strip():
        return None
    return git(project, "merge-base", ref, "HEAD").strip() or None


def added_lines(project, base, path, text):
    """1-basierte Zeilen im Arbeitsbaum; ohne Basis ist alles Bestand."""
    if not base:
        return set()
    if path in git(project, "ls-files", "--others", "--exclude-standard", "-z").split("\0"):
        return set(range(1, len(text.splitlines()) + 1))
    out = git(project, "diff", "-U0", base, "--", path)
    added = set()
    cur = None
    for line in out.splitlines():
        if line.startswith("@@"):
            match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            cur = int(match.group(1)) if match else None
        elif cur is not None and line.startswith("+") and not line.startswith("+++"):
            added.add(cur)
            cur += 1
        elif cur is not None and line.startswith(" "):
            cur += 1
    return added
