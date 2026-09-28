# Report

Ziel: `docs/quality-report.md` im geprüften Projekt, vollständig ersetzt.

`docs/` existiert an dieser Stelle immer — das Script hat es für seine eigene
Ablage bereits angelegt. Du erzeugst keine Verzeichnisse.

Der Report hat zwei Leser: ein Mensch, der entscheidet, und ein Coding-Agent, der
abarbeitet. Deshalb ist jeder Befund einzeln adressierbar — mit ID, Pfad und
Zeile. Fasse dich in der Konversation auf drei Sätze plus Verdikt und Dateipfad
zusammen; die Substanz steht in der Datei.

## Kein YAML-Frontmatter

Du beginnst den Report mit der Überschrift, **nie** mit einem `---`-Block.

Im wöchentlichen Turnus (`bin/guard-weekly`) trägt das Script danach selbst ein
Frontmatter ein, das den Bearbeitungsstand festhält:

```yaml
---
guard_status: open          # open = Befunde offen · acknowledged = abgearbeitet
generated_at: 2026-09-13T03:00:00+02:00
guard_branch: develop
commit: a1b2c3d
acknowledged_at:
acknowledged_commit:
---
```

Solange `guard_status: open` steht, überschreibt kein Turnuslauf die Datei —
Sie werden gerade abgearbeitet. Abgehakt wird mit
`guard-weekly --acknowledge`, erst danach wird neu gemessen.

Dieser Zustand entscheidet über den nächsten Lauf und wird deshalb bewusst nicht
von einem Modell geschrieben. Schreibst du selbst ein Frontmatter, wird es
ersetzt; ein `guard_status`, den du setzt, hat keine Wirkung.

## Aufbau

```markdown
# Qualitäts-Report — <Projekt>

**Verdikt:** GREEN | YELLOW | RED | INCOMPLETE
**Guard-Script:** <verdict aus docs/.guard/results.json> · **Policy:** erfüllt | verletzt
**Stand:** <ISO-Datum> · **Commit:** <kurzer Hash> · **Branch:** <name>
**Abdeckung:** <x> von <y> anwendbaren Checks ausgeführt, davon <n> grün

<Zwei Sätze: was trägt, was nicht.>

## Übersicht

| Bereich | Werkzeug/Check | Verfügbarkeit | Ausführung | Ergebnis | Beleg |
|---|---|---|---|---|---|

## Wie das Verdikt zustande kommt

Das Script-Verdikt setzt die Untergrenze, dein Review kann sie nur **verschärfen**,
nie aufweichen:

| Script sagt | Report-Verdikt mindestens |
|---|---|
| `UNSAFE` | RED — und der Report endet hier, siehe „Nebenwirkungen" |
| `FAIL` | RED |
| `INCOMPLETE` | INCOMPLETE |
| `PASS_WITH_GAPS` | YELLOW — die Lücken sind Befunde, kein Erfolg |
| `PASS` | GREEN |

Darüber legen sich die Schwellen aus `guard-policy.yml`:

- ein `BLOCKER` oder `HIGH` über der Schwelle → **RED**
- mehr `MEDIUM` als erlaubt → **YELLOW**, nie schlechter als das Script sagt
- beliebig viele `LOW` → ändern das Verdikt nie

Ein hochgestuftes `PASS → WARN` (siehe Statusvokabular in der SKILL.md) macht aus
GREEN mindestens YELLOW.

**RED schlägt INCOMPLETE.** Fehlen kritische Checks, gibt es aber belegte
Befunde über der Schwelle, ist das Verdikt RED — ein nachgewiesener Blocker
wird durch fehlende Messungen nicht unsicherer. Im Kopf steht dann zusätzlich,
welche kritischen Checks fehlten.

## Projektprofil

Ergebnis von Schritt 0 (siehe `project-profile.md`):

| Wert | Stand | Quelle |
|---|---|---|
| mandanten | spalte (`organisation`) | abgeleitet: `src/Entity/Order.php:7` |
| datenbank | unbekannt | keine `.env` |

Gibt es `.ai/guard-profile.yml` nicht, steht hier zusätzlich ein Vorschlag, der
mit `bin/guard-profile-draft` erzeugt werden kann.

## Anforderungsdeckung

Nur wenn eine Anforderung greifbar war (Auftrag, Ticket, Spezifikation). Sonst
diesen Abschnitt weglassen und im Kopf `Anforderung: N/A` vermerken — niemals
eine Deckung gegen eine selbst ausgedachte Anforderung behaupten.

```
✓ <Teilanforderung>        <Datei:Zeile als Beleg>
✗ <Teilanforderung>        kein Beleg gefunden
```

Hat es statt einer Anforderung nur die Commit-Nachricht gegeben, heißt dieser
Abschnitt „Konsistenzprüfung gegen die Commit-Nachricht“ — und im Kopf steht
`Anforderung: N/A (nur Commit-Nachricht geprüft)`.

## Gates

<Die tatsächlich konfigurierten Schwellen und ob sie gehalten haben.>

## Muss behoben werden

Alles mit Severity `BLOCKER` oder `HIGH` nach `guard-policy.yml`.

### Q1 — <Titel>
- **Severity:** BLOCKER | HIGH
- **Datei:** `pfad/zur/datei.php:42`
- **Quelle:** phpstan (Level 8) | Achse 2 (erfundene Symbole) | …
- **Befund:** <ein Satz>
- **Beleg:** `docs/.guard/logs/phpstan.log` oder die Codestelle, die es beweist
- **Auftrag:** <was zu tun ist, eng genug für einen Coding-Agenten>

## Sollte verbessert werden

<Gleiche Struktur, IDs Q<n> fortlaufend. Severity MEDIUM oder LOW.>

## Sonstiges

Belegte Befunde außerhalb der Achsen (siehe `semantic-review.md`), mit Severity.

## Bewusste Ausnahmen

Befunde, die auf eine Ausnahme aus `.ai/guard-profile.yml` treffen: Befund,
Ausnahme, Grund. Sie zählen nicht gegen die Schwellen.

## Vorbestand

Probleme in Code, den der Diff nicht anfasst. Sie zählen nie gegen die
Schwellen, gehören aber erwähnt.

## Tooling-Lücken

<Fehlt vs. installiert-aber-unkonfiguriert, mit exakten Paketnamen.>

## Ratsche

<Gemessene Werte als Startboden — nur Zahlen, die ein Werkzeug geliefert hat:
PHPStan-Level, Coverage-Prozent, MSI, Anzahl Baseline-Einträge, Anzahl
Advisories. Keine selbst geschätzte Gesamtnote: eine Zahl, die beim nächsten Lauf
anders gerechnet wird, taugt nicht als Boden.>

## Nebenwirkungen

- Worktree vor Lauf: <n> geänderte Dateien
- Worktree nach Lauf: <n> geänderte Dateien — **unverändert** | **ABWEICHUNG**
- Container gestartet: <ja/nein, welche>
- Test-Datenbank migriert: <ja/nein>

## Nächste drei Schritte

1. Q<n> — <Titel>
2. …
3. …
```

## Verdikt

`INCOMPLETE` gilt, sobald fehlende oder blockierte kritische Checks ein
belastbares Urteil verhindern. Verrechne eine fehlende kritische Kontrolle
niemals zu einem beruhigenden Mittelwert.

Bewerte nur beobachtete Dimensionen und zeige die Abdeckung der Bewertung
(`78/100 über 6 von 9 anwendbaren Checks`). Begründe Abzüge knapp. Halte
**Bewertungsabdeckung** und **Code-Coverage** streng auseinander.

## Belege

Gib zu jedem ausgeführten Befehl die Dauer an, wenn verfügbar, und erhalte die
Bedeutung des Exit-Codes. Kleb keine großen Logs ein — zitiere nur die
entscheidende Zeile und verweise auf repräsentative Fundstellen.

## Aufträge

Jeder Punkt unter *Muss* und *Sollte* trägt einen **Auftrag**, der eng genug
formuliert ist, dass ein lokales Modell ihn treffen kann: Zieldatei, erwartetes
Verhalten, das Gate, das danach grün sein muss. Das ist der Grund für die
Datei — ohne diese Schärfe kann der Coding-Agent nichts damit anfangen.

Alle Punkte bleiben Empfehlungen. Du setzt keinen davon um.

## Sprache

Der Report ist deutsch und orthografisch sauber: `ä`, `ö`, `ü`, `ß` korrekt
gesetzt — `Verstoß`, `gemäß`, `Größe`, `Schlüssel`. Ein Report, der selbst
`Verstoss` schreibt, untergräbt seinen eigenen Befund zur Textqualität.
