# Semantisches Review

Diese Achsen laufen **nach** `bin/code-guard`. Alles, was ein Werkzeug messen
kann, hat das Script bereits gemessen — hier prüfst du nur, was keinen Linter
hat. Wenn du hier Zeit auf Dinge verwendest, die PHPStan ohnehin findet, ist der
Lauf verschwendet.

Grundlage ist immer der **Diff**, nicht das ganze Projekt:
`git diff <base>...HEAD` plus die uncommitteten Änderungen. Die Basis und die
Liste der geänderten Dateien stehen in `docs/.guard/results.json` unter
`git.base_ref` und `git.changed_files`.

Jeder Befund braucht Pfad, Zeile und eine Severity aus `guard-policy.yml`.
Ohne Codebeleg ist es kein Befund, sondern eine Vermutung — und die gehört
gekennzeichnet oder weggelassen.

## Achse 1 — Anforderungsdeckung

Die häufigste Art, wie KI-generierter Code scheitert: Er ist sauber, grün und
setzt die Aufgabe trotzdem nur zur Hälfte um.

Du brauchst dafür die ursprüngliche Aufgabe. Quellen, in dieser Reihenfolge:

1. **Der Auftrag in der Konversation.** Sagt er ausdrücklich, dass es keine
   Anforderung gibt, ist die Achse `N/A` — auch dann, wenn du selbst eine
   Quelle findest. Die Ansage des Auftraggebers schlägt deinen Fund.
2. **Ein Ticket** (Vikunja, Redmine, GitLab-Issue).
3. **Eine Spezifikation** unter `docs/`.
4. **Die Commit-Nachricht** — aber nur als *schwache* Quelle. Sie beschreibt,
   was der Autor zu tun glaubte, nicht, was verlangt war. Prüfst du gegen sie,
   nenne das Ergebnis im Report **„Konsistenzprüfung gegen die
   Commit-Nachricht"** und ausdrücklich nicht Anforderungsdeckung. Ein
   Widerspruch zwischen Commit-Aussage und Code ist trotzdem ein Befund, meist
   `MEDIUM`.

Findest du keine dieser Quellen, ist die Achse `N/A` — behaupte niemals Deckung
gegen eine Anforderung, die du dir selbst zusammengereimt hast.

Zerlege die Anforderung in einzelne, prüfbare Aussagen und belege jede am Code:

```
✓ Nutzer kann eine Datei hochladen        UploadController.php:44
✓ Nur PDF erlaubt                          UploadType.php:31 (MimeTypes-Constraint)
✓ Maximal 10 MB                            UploadType.php:34
✗ Fehlerfall wird protokolliert            kein Beleg gefunden
✗ Audit-Log-Eintrag                        kein Beleg gefunden
```

Eine unbelegte Anforderung ist `HIGH`, wenn sie im Auftrag ausdrücklich stand.

## Achse 2 — Erfundene Symbole

Ein lokales Modell erfindet unter Druck Dinge, die plausibel klingen. Das ist
der teuerste Fehler, weil er oft erst zur Laufzeit auffällt.

Prüfe jedes im Diff **neu verwendete** Symbol gegen seine Quelle:

| Was | Wogegen belegen |
|---|---|
| Service, per Autowiring injiziert | Klasse existiert; `make -n` oder `config/services.yaml` |
| Aufgerufene Methode | Deklaration in Klasse, Elternklasse oder Trait |
| Composer-Paket | steht in `composer.json` **und** `composer.lock` |
| ENV-Variable | `.env`, `.env.dist` oder `config/` — sonst fällt sie still auf einen Default zurück |
| Config-Key / Parameter | `config/**/*.yaml` |
| Twig-Filter/-Funktion | Extension im Projekt oder Symfony-Standard |
| Route-Name in `generateUrl()` | eine `#[Route(name: ...)]` im Projekt |

Belege heißt: Datei und Zeile nennen können. „Sieht üblich aus" ist kein Beleg.

Eine erfundene ENV-Variable ist besonders heimtückisch — sie stürzt nicht ab,
sondern nimmt still den Vorgabewert. Das ist mindestens `HIGH`.

## Achse 3 — Autorisierung

Statische Analyse sieht, **ob** geprüft wird, nicht **was**. Der klassische
Fehler sieht so aus:

```php
#[Route('/kunde/{id}')]
#[IsGranted('ROLE_USER')]
public function show(Customer $customer): Response
```

Geprüft wird, dass jemand eingeloggt ist. Nicht geprüft wird, ob **dieser**
Nutzer **diesen** Kunden sehen darf. Jede neue oder geänderte Route mit einem
Parameter, der auf einen Datensatz zeigt, wird gegen diese Frage geprüft.

Weitere Stellen: Massenoperationen ohne Mandantenfilter, Repository-Methoden
ohne Einschränkung auf den Besitzer, API-Endpunkte, die eine ID direkt aus dem
Request nehmen. Fehlende Objektberechtigung ist `HIGH`, bei Kundendaten `BLOCKER`.

## Achse 4 — Datenbank und Migration

Nur wenn der Diff Entities, Repositories oder Migrationen berührt.

1. **Entity geändert, aber keine Migration im Diff?** → `HIGH`.
2. **Migration nicht umkehrbar** (`down()` leer oder wirft) → `HIGH`.
3. **`NOT NULL`-Spalte ohne Default auf eine bestehende Tabelle** → `BLOCKER`.
   Das Deployment scheitert, sobald Zeilen existieren.
4. **Fehlender Index** auf einer Spalte, die neu in `WHERE`, `JOIN` oder
   `ORDER BY` auftaucht → `MEDIUM`.
5. **N+1**: eine Schleife über eine Collection, die je Durchlauf einen
   Lazy-Load auslöst. Beleg ist die Schleife plus der fehlende `JOIN`/`fetch` →
   `MEDIUM`, in einer Liste ohne Obergrenze `HIGH`.
6. **Datenverändernde Migration ohne Backup-Hinweis** bei `DELETE`, `UPDATE`
   oder `DROP COLUMN` → `BLOCKER`.

## Achse 5 — Architektur

Siehe `architecture.md`. Hier gilt zusätzlich: Bewerte nur den Diff, und nur
gegen Regeln, die im Projekt tatsächlich niedergeschrieben sind — `CLAUDE.md`,
`AGENTS.md`, `docs/`, `deptrac.yaml`. Eine Regel, die nur du für richtig hältst,
ist ein Vorschlag mit Severity `LOW`, kein Verstoß.

## Was du nicht tust

- Keine Stilmeinung ohne Regel im Projekt.
- Keine Befunde zu Code, den der Diff nicht anfasst — Altlasten gehören in den
  Abschnitt „Vorbestand", nicht in die Blockerliste.
- Kein Nacherzählen der Werkzeugausgaben. Das Script hat sie schon protokolliert;
  du verweist auf `docs/.guard/logs/<check>.log`.
- Keine Severity nach Gefühl. Die Stufen stehen in `guard-policy.yml`.
