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
Ohne Codebeleg ist es kein Befund, sondern eine Vermutung. Eine Vermutung steht
höchstens als `LOW` im Report, mit dem Wort „Vermutung“ im Titel — oder sie
entfällt. Sie hebt das Verdikt nie.

**Rangfolge der Severity:** Nennt eine Achse eine Severity ausdrücklich (etwa
„Datenleck zwischen Mandanten bei Kundendaten: BLOCKER“), gilt sie vor den
allgemeinen Beschreibungen in `guard-policy.yml`. Die Policy regelt Schwellen
und Stufen, die Achse ist die speziellere Regel.

**Ein Defekt, ein Befund:** Trifft dieselbe Ursache mehrere Achsen (ein
Mandant aus dem Request ist Achse 3 und 6), wird daraus **ein** Befund. Er
steht unter der Achse mit der höchsten Severity, die übrigen folgen in Klammern
(„Achse 6 (+3)“), und er zählt einmal gegen die Schwellen. Nennen zwei Achsen
für denselben Defekt unterschiedliche Severities, gilt die **höchste**.

Wo ein Defekt endet, entscheidet die **Behebung**: Was mit einer Änderung
behoben ist, ist ein Befund. Ein ungesicherter Webhook ohne Signaturprüfung, ohne
Idempotenz und ohne Payload-Prüfung sind drei Befunde — drei Änderungen.

**Befunde außerhalb der Achsen** sind erlaubt, wenn sie belegt sind — etwa ein
abgeschalteter CSRF-Schutz oder `flush()` ohne Validierung. Sie stehen unter
„Sonstiges“, die Severity folgt den Beschreibungen in `guard-policy.yml`.

## Schritt 0 — Projektprofil

Lies zuerst `.ai/guard-profile.yml` des Projekts (Format und Regeln in
`project-profile.md`). Es entscheidet, welche Achsen laufen: Mandantentrennung
nur mit Mandanten, Autorisierung nur mit Anmeldung. Fehlt das Profil oder ein
Wert, ist er **unbekannt, nicht „trifft nicht zu“** — bestimme ihn aus dem Code
und nenne im Report, woraus. Eine Achse ist nur dann `N/A`, wenn das Profil sie
ausdrücklich abschaltet, der Diff ihren Gegenstand nicht berührt oder die
Achse selbst einen Grund nennt (Achse 5: keine niedergeschriebenen Regeln).

Das Ergebnis von Schritt 0 steht im Report unter „Projektprofil“: gelesene
Werte, abgeleitete Werte mit Quelle, offen gebliebene Werte.

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

Sagt der Auftrag ausdrücklich, dass es keine Anforderung gibt, ist die Achse
`not_applicable`. Findest du schlicht keine Quelle, ist sie `needs_context` —
behaupte niemals Deckung gegen eine Anforderung, die du dir selbst
zusammengereimt hast. Eine Konsistenzprüfung gegen die Commit-Nachricht darf
trotzdem Befunde liefern; der Status bleibt `needs_context`.

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

**Gegen die installierte Version prüfen, nicht gegen das Gedächtnis.** Ein
Modell kennt eine API oft aus einer anderen Major-Version: `Connection::fetchAll()`
gibt es seit doctrine/dbal 3 nicht mehr, und `protected static $defaultName` für
Konsolen-Befehle ist seit symfony/console 6.1 veraltet (dort `#[AsCommand]`).
Für jede neu verwendete
Methode oder Option eines Pakets:

1. Version aus `composer.lock` lesen (`packages[].version`).
2. Die Deklaration in `vendor/<paket>/` suchen — Methode, Option oder
   Konstante muss dort existieren. `@deprecated` im Docblock ist ein Befund
   `MEDIUM`, eine fehlende Methode `HIGH`.
3. Fehlt `vendor/` (nicht installiert), ist **diese Teilprüfung**
   `needs_context` — nicht „gegeben“. Die übrigen Teile der Achse (Services,
   ENV, Paketdeklaration) laufen trotzdem, und der Achsenstatus richtet sich
   nach ihnen.
4. Ohne `vendor/` darfst du einen dir bekannten Bruch nicht als belegt melden.
   Er steht als `LOW` mit „Vermutung“ im Titel und dem Auftrag „nach
   `composer install` erneut prüfen“. Belegt wird er erst am Code in `vendor/`.
5. Ein `composer.lock` ohne `content-hash` hat nicht Composer erzeugt; die
   Versionen darin sind nicht belastbar → `needs_context`.

Nenne im belegten Befund die Version und die Fundstelle: „`fetchAll()` existiert
in doctrine/dbal 3.10.5 nicht — `vendor/doctrine/dbal/src/Connection.php`
deklariert nur `fetchAllAssociative()` u. a.“.

Eine erfundene ENV-Variable ist besonders heimtückisch — sie stürzt nicht ab,
sondern nimmt still den Vorgabewert. Das ist mindestens `HIGH`.

Unterscheide **erfunden** und **nicht deklariert**: Eine Klasse, die es in keinem
Paket gibt, ist erfunden (`HIGH`). Eine echte Klasse aus einem Paket, das nur
nicht in `composer.json` steht, ist nicht deklariert — ebenfalls `HIGH`, weil
die Anwendung nach `composer install` nicht startet, aber mit dem Hinweis auf
das fehlende Paket statt auf eine erfundene API.

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

Wenn der Diff auf die Datenbank zugreift: Entities, Repositories,
Migrationen — aber auch rohes SQL über DBAL, `createNativeQuery` oder DQL in
Controllern und Services. Neue Tabellen, Spalten und Filter im rohen SQL
brauchen denselben Beleg (Mapping oder Migration) wie eine Entity-Änderung.

1. **Entity geändert, aber keine Migration im Diff?** → `HIGH`.
2. **Migration nicht umkehrbar** (`down()` leer oder wirft) → `HIGH`.
3. **`NOT NULL`-Spalte ohne Default auf eine bestehende Tabelle** → unter
   PostgreSQL `BLOCKER`, das Deployment scheitert, sobald Zeilen existieren.
   MySQL/MariaDB füllen still einen impliziten Wert (`0`, `''`) ein → `MEDIUM`,
   wenn dieser Wert fachlich falsch ist (etwa ein Status oder eine Menge).
   Das Script (`migrations`) meldet den Fall bereits; hier bewertest du nur die
   fachliche Folge.
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

## Achse 6 — Mandantentrennung

Nur wenn das Profil Mandanten nennt oder der Code sie erkennen lässt (siehe
`project-profile.md`). Ein Datenleck zwischen Mandanten ist bei Kundendaten
immer `BLOCKER`.

Prüfe jeden neuen oder geänderten Lese- und Schreibpfad:

1. **Woher kommt der Mandant?** Er muss aus der verifizierten Identität folgen
   (angemeldeter Nutzer, geprüftes Token), nie aus einem Request-Parameter,
   Header, Formularfeld oder einer Subdomain, die der Nutzer frei wählen kann,
   ohne dass seine Zugehörigkeit geprüft wird.
2. **Greift die Isolation überall?** Ein zentraler Doctrine-Filter schützt DQL
   und Repositories — aber nicht rohes SQL über DBAL, nicht Exporte, Reports,
   Suchindizes, Caches, Dateiablagen und nicht Konsolen-Befehle, in denen der
   Filter oft gar nicht aktiv ist. Jede Abfrage außerhalb des zentralen Wegs
   braucht den Mandanten ausdrücklich im `WHERE`.
3. **Worker und Befehle:** Setzt ein Message-Handler oder Command den
   Mandantenkontext, muss er ihn nach dem Auftrag zurücksetzen. Sonst läuft der
   nächste Auftrag im Kontext des vorigen Mandanten.
4. **Schreiben mit fremden Referenzen:** Nimmt ein Formular oder eine API eine
   ID an (Kategorie, Kunde, Datei), muss geprüft werden, dass der referenzierte
   Datensatz zum selben Mandanten gehört. Sonst hängt man fremde Daten an.
5. **Caches:** Enthält ein Cache-Schlüssel Daten eines Mandanten, gehört der
   Mandant in den Schlüssel.

Beleg ist immer der konkrete Pfad, auf dem ein Nutzer von Mandant A Daten von
Mandant B sieht oder ändert — nicht die bloße Abwesenheit eines Filters.

## Achse 7 — Injection und Mass Assignment

Nur für Code im Diff, der Eingaben verarbeitet: Controller, Formulare,
Deserializer, API-Plattform-Ressourcen, Konsolen-Befehle, Message-Handler.
`app-static` meldet Muster (SQL mit Variable, `exec`), kann aber nicht
entscheiden, ob der Wert wirklich aus einer Eingabe stammt. Das tust du.

Verfolge jeden Wert rückwärts bis zu seiner Quelle. Stammt er aus Request,
Formular, Header, Cookie, Datei, Webhook oder einer externen API, gilt er als
unvertrauenswürdig:

| Ziel | Befund, wenn … | Severity |
|---|---|---|
| SQL, DQL | der Wert eingesetzt statt gebunden wird; auch `ORDER BY`/Spaltennamen aus Eingaben ohne Positivliste | `BLOCKER` |
| Shell | der Wert in `exec`, `shell_exec`, `Process::fromShellCommandline` landet, ohne als Argumentliste übergeben zu werden | `BLOCKER` |
| HTTP-Aufruf | die Ziel-URL oder der Host aus der Eingabe stammt, ohne Positivliste (SSRF auf interne Dienste, Metadaten-Endpunkte) | `HIGH` |
| Dateisystem | ein vom Nutzer gelieferter Dateiname Pfadbestandteil wird (`../`) | `HIGH` |
| Weiterleitung | eine Ziel-URL aus der Eingabe kommt (Open Redirect) | `MEDIUM` |

**Mass Assignment:** Ein Formular, das direkt an eine Entity gebunden ist, oder
ein Deserializer ohne Gruppen darf keine Felder beschreibbar machen, die der
Nutzer nicht setzen darf: Rollen, `isAdmin`, Besitzer, Mandant, Preis, Status,
Freigabe. Prüfe bei jedem neuen Feld im FormType und bei jeder neuen
Deserialisierung, welche Felder beschreibbar sind. Ein beschreibbares Rechte- oder
Besitzerfeld ist `BLOCKER`, ein beschreibbarer Preis oder Status `HIGH`.

## Achse 8 — Datenabfluss

Nur für Code im Diff, der Antworten, Serialisierung, Logs oder Fehlermeldungen
berührt.

1. **Entities als Antwort:** `$this->json($entity)`, `serialize($entity)` oder
   eine API-Ressource ohne Serializer-Gruppen gibt alle Felder heraus —
   Passwort-Hash, Tokens, interne Notizen, Relationen zu anderen Nutzern.
   Nachgewiesener Abfluss eines vertraulichen Felds ist `HIGH`, bei Passwort-Hash
   oder Token `BLOCKER`.
2. **Logs:** Passwörter, Tokens, API-Schlüssel, vollständige Request- oder
   Response-Bodies von Zahlungs- und Auth-Aufrufen gehören nicht ins Log. Auch
   nicht auf `debug`. `HIGH`.
3. **Fehlermeldungen:** Exception-Texte, SQL, Pfade oder Konfigurationswerte in
   Antworten an Nutzer. `MEDIUM`, mit Geheimnis `HIGH`.
4. **Öffentlicher Cache:** Eine Antwort mit personenbezogenen Daten darf nicht
   `public` oder mit `s-maxage` ausgeliefert werden. `BLOCKER`.

Beleg ist das konkrete Feld, das nach außen geht, und der Weg dorthin.

## Achse 9 — Integrationen und Wiederholungen

Nur für Code im Diff, der externe Dienste aufruft (HTTP-Clients, SDKs, Mail,
Zahlung, Versand), Webhooks annimmt oder Messenger-Handler enthält.

| Frage | Befund, wenn … | Severity |
|---|---|---|
| Zeitbudget | ein externer Aufruf ohne `timeout`/`max_duration` läuft (auch nicht über die Client-Konfiguration) | `MEDIUM` |
| Wiederholung | Retries unbegrenzt sind, ohne Backoff laufen oder auch bei 4xx wiederholen | `MEDIUM` |
| Schreibaufrufe | ein schreibender Aufruf (Zahlung, Bestellung, Mail) nach Timeout blind wiederholt wird, ohne Idempotenzschlüssel oder Abgleich | `HIGH`, bei Geld `BLOCKER` |
| Antwort | eine externe Antwort ungeprüft weiterverwendet wird (Struktur, Status, Pflichtfelder) | `MEDIUM`, führt es zu falschen Zahlungs- oder Bestandsdaten `HIGH` |
| Webhook | die Signatur nicht **vor** der fachlichen Verarbeitung geprüft wird | `HIGH` |
| Doppelte Zustellung | ein Webhook oder eine Nachricht bei zweiter Zustellung doppelt wirkt (zweite Buchung, zweite Mail) | `HIGH` |
| Nebeneffekte im Handler | ein Messenger-Handler erst schreibt und dann scheitert, sodass der Retry den Nebeneffekt wiederholt | `HIGH` |

Zeitbudget und Wiederholung betreffen **ausgehende** Aufrufe. Für eingehende
Webhooks gelten Signatur, Payload-Prüfung und doppelte Zustellung. Eine fehlende
Signatur, über die Fremde fachliche Zustände ändern können (Bestellung auf
„bezahlt“), ist wie fehlende Autorisierung zu werten: bei Kundendaten oder Geld
`BLOCKER`.

Beleg ist der konkrete Ablauf: „Webhook `payment.succeeded` bucht in
`PaymentWebhookController.php:52`, ohne zu prüfen, ob die Zahlungs-ID schon
verbucht ist — Stripe stellt Webhooks mindestens einmal zu.“

## Achse 10 — Fehlerbehandlung

Für jeden neuen oder geänderten `try`/`catch`, jedes neue `return` im Fehlerpfad
und jeden neuen Fallback.

1. **Fehler als Erfolg:** Ein Fehlerpfad gibt `true`, `[]`, `null` oder HTTP 200
   zurück, obwohl die Aktion nicht stattfand. `HIGH`.
2. **Zu breites Fangen:** `catch (\Throwable)` bzw. `catch (\Exception)` ohne
   erkennbare Strategie (weder protokolliert noch umgewandelt noch weitergeworfen).
   `MEDIUM`, im Zahlungs- oder Datenpfad `HIGH`.
3. **Ursache verloren:** Beim Umverpacken fehlt die ursprüngliche Exception als
   `previous`. `LOW`.
4. **Stiller Fallback:** Ein Standardwert ersetzt einen fehlgeschlagenen Wert so,
   dass Datenverlust oder falsche Ergebnisse unbemerkt bleiben (leerer Preis,
   Standardmandant, heutige statt gelieferter Datum). `HIGH`.
5. **Aufräumen:** Ressourcen (Dateien, Locks, temporäre Daten) werden im
   Fehlerfall nicht freigegeben — kein `finally`. `MEDIUM`. Fehlende
   Transaktionen und `rollback()` gehören zu Achse 11.

Treffen „Fehler als Erfolg“ und „zu breites Fangen“ dieselbe Stelle, ist das ein
Befund.

Das Script meldet leere `catch`-Blöcke bereits (`gate-integrity`); hier geht es
um die, die etwas tun — nur das Falsche.

## Achse 11 — Nebenläufigkeit und Datenintegrität

Nur bei Diffs, die Schreibpfade berühren: Speichern, Zählen, Reservieren,
Buchen, eindeutige Nummern vergeben.

1. **Eindeutigkeit per SELECT:** „Gibt es das schon? Sonst anlegen“ ohne
   Unique-Constraint in der Datenbank. Zwei gleichzeitige Requests legen beide an.
   `HIGH`.
2. **Lost Update:** Lesen, im Code ändern, zurückschreiben (Lagerbestand,
   Guthaben, Zähler) ohne Versionierung (`#[ORM\Version]`), Sperre
   (`PESSIMISTIC_WRITE`) oder atomares `UPDATE … SET x = x - 1`. `HIGH`, bei Geld
   oder Bestand `BLOCKER`.
3. **Invarianten nur im Code:** Eine Regel wie „Nummer eindeutig“ oder „nie
   leer“ steht nur in der Validierung, nicht als Constraint bzw. `NOT NULL`.
   `MEDIUM`.
4. **Transaktionsgrenzen:** Zusammengehörige Schreibvorgänge liegen nicht in
   einer Transaktion, oder in einer Transaktion steckt ein langsamer externer
   Aufruf. `MEDIUM`.
5. **Doppelklick:** Ein Formular oder Endpunkt, der bei doppeltem Absenden durch
   einen Nutzer doppelt wirkt (zweite Bestellung). `MEDIUM`. Doppelte Zustellung
   durch einen externen Dienst gehört zu Achse 9.

Lost Update und eine Invariante, die nur im Code steht („Bestand nie negativ“),
sind beim selben Wert ein Befund.

Beleg ist der Ablauf mit zwei gleichzeitigen Requests, nicht die bloße
Abwesenheit eines Locks.

## Was du nicht tust

- Keine Stilmeinung ohne Regel im Projekt.
- Keine Befunde zu Code, den der Diff nicht anfasst — Altlasten gehören in den
  Abschnitt „Vorbestand", nicht in die Blockerliste.
- Kein Nacherzählen der Werkzeugausgaben. Das Script hat sie schon protokolliert;
  du verweist auf `docs/.guard/logs/<check>.log`.
- Keine Severity nach Gefühl. Die Stufen stehen in `guard-policy.yml`.
