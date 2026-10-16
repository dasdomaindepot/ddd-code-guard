# Sicherheitswissen im Projekt

Eine Tiefenprüfung kann Wissen für spätere Diff-Reviews unter `docs/security/`
ablegen. Der Ordner ist optional. Das Diff-Review liest vorhandene Dateien,
erstellt und verändert sie aber nicht. Die Erzeugung durch einen Tiefenscan
ist nicht Teil des Code Guards.

## Dateien und Git-Grenze

| Datei | Inhalt | Git |
|---|---|---|
| `threat-model.md` | Vertrauensgrenzen, Angreifer, kritische Werte und betroffene Pfade | einchecken |
| `history.jsonl` | frühere Sicherheitsfixes aus der Git-Historie | einchecken |
| `findings.jsonl` | Funde samt Begründungen und möglichen Angriffswegen | lokal halten |

Das Projekt legt `docs/security/.gitignore` selbst an und checkt es ein:

```gitignore
/findings.jsonl
```

Die Regel gilt nur für die Funddetails. `threat-model.md` und `history.jsonl`
bleiben für das Team sichtbar. Der Code Guard erzeugt diese `.gitignore` nicht.
Ein bereits eingechecktes `findings.jsonl` wird durch eine Ignore-Regel nicht
aus Git entfernt; vor dem Einchecken mit `git ls-files docs/security/findings.jsonl`
prüfen. Auch versionierte Dateien dürfen keine Geheimnisse, internen Hosts oder
Schrittfolgen zur Ausnutzung enthalten.

## `threat-model.md`

Freier Markdown-Text mit diesen Abschnitten:

```markdown
# Bedrohungsmodell

## Kritische Werte
- Kundendaten und Sitzungstoken

## Angreifer
- Nicht angemeldete Besucher
- Angemeldete Nutzer mit Zugriff auf eigene Datensätze

## Vertrauensgrenzen
- Eingaben aus HTTP-Anfragen werden vor Datenbankzugriff und HTML-Ausgabe geprüft.
- Ein Nutzer darf nur Datensätze seiner Organisation lesen und ändern.

## Heikle Stellen
- `src/Controller/ExportController.php`: Berechtigung für den Export.
```

Grenzen und Stellen so konkret beschreiben, dass ein späteres Review geänderte
Pfade und Datenflüsse zuordnen kann. Pfade sind Hinweise, keine abschließende
Positivliste: Umbenennungen und neue Aufrufpfade mitprüfen.

## `history.jsonl`

UTF-8, eine gültige JSON-Struktur pro Zeile, keine umschließende Liste. Ein
Eintrag beschreibt einen belegten Sicherheitsfix aus der Git-Historie:

```json
{"commit":"0123456789abcdef0123456789abcdef01234567","datum":"2026-01-15","dateien":["src/Controller/ExportController.php"],"fehlerklasse":"Fehlende Objektberechtigung","schutz":"Export prüft die Zugehörigkeit des Datensatzes zum Nutzer"}
```

`commit` ist der vollständige Git-Hash, `datum` das Commit-Datum im Format
`JJJJ-MM-TT`, `dateien` die damals betroffenen Pfade. `fehlerklasse` und `schutz`
erklären, welches Muster nicht zurückkehren darf. Sie enthalten keine
Angriffsschritte. Beim Review den Commit und den heutigen Code lesen; ein
alter Pfad allein belegt noch keine Regression.

## `findings.jsonl`

Gleiches JSONL-Format. Ein Eintrag enthält mindestens:

```json
{"fingerabdruck":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","status":"verworfen","datei":"src/Controller/ExportController.php","zeile":42,"beschreibung":"Beobachteter Datenfluss und seine Sicherheitsfolge","begründung":"Der Datenfluss ist durch eine vorgeschaltete Berechtigungsprüfung geschützt."}
```

`fingerabdruck` ist eine stabile Kennung für denselben Befund, nicht für die
Zeilennummer. `datei` ist ein relativer Projektpfad. `status` ist genau
`offen`, `bedingt`, `erledigt` oder `verworfen`. `beschreibung` hält den Fund nachvollziehbar
fest; `zeile` ist eine positive, bei offenen und bedingten Funden vorhandene
Dateizeile. `offen` verlangt `severity` (`BLOCKER`, `HIGH`, `MEDIUM`, `LOW`)
sowie `angreifer`, `grenze` und `wirkung`. `bedingt` hat keine Severity und
verlangt `offene_voraussetzung`: die fehlende Tatsache außerhalb des Codes
und eine gefahrlose Prüfung durch den Betreiber. Bei `erledigt` nennt
`begründung` die Behebung, bei `verworfen` den konkreten Grund für den
Fehlalarm. `belege` kann weitere projekt-relative `pfad:zeile`-Angaben enthalten.
Fingerabdrücke sind innerhalb eines Laufs eindeutig. Ein Fund kann
bei erneutem Auftreten mit demselben Fingerabdruck aktualisiert werden. Die
Datei bleibt lokal, auch wenn sie nur scheinbar harmlose Details enthält.

Eine öffentliche Kurzliste ist für das Diff-Review nicht erforderlich. Falls
ein Projekt sie zusätzlich braucht, darf jeder Eintrag ausschließlich
`fingerabdruck`, `status` und `datei` enthalten, ohne Beschreibung, Begründung
oder Angriffsweg.
