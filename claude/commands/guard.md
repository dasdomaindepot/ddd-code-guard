---
description: Code Guard — deterministische Gates plus semantisches Review, Ergebnis als docs/quality-report.md
argument-hint: "[projektverzeichnis] [--full]"
---

Starte den Code Guard für das aktuelle Projekt (oder für `$ARGUMENTS`, falls
dort ein Verzeichnis genannt ist).

Fahre das über den `code-quality`-Subagenten, nicht selbst — er hat die engeren
Schranken und hält das Prüfergebnis aus dem laufenden Coding-Kontext heraus.

Auftrag an den Agenten:

1. `~/.claude/skills/code-quality/bin/code-guard --no-color`
   ausführen (mit `--full`, wenn das in `$ARGUMENTS` steht).
2. `docs/.guard/results.json` auswerten, bei roten Checks die Logs unter
   `docs/.guard/logs/` lesen.
3. Das Projektprofil `.ai/guard-profile.yml` lesen und den Diff gegen die Achsen
   aus `references/semantic-review.md` prüfen, die das Profil verlangt.
4. `guard-policy.yml` anwenden und `docs/quality-report.md` schreiben.
5. Keinen Projektcode ändern.

Melde mir danach: Verdikt, die wichtigsten Blocker, ein `file://`-Link auf den
Report — und ob der Worktree unverändert geblieben ist.
