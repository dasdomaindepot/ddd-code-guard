# Projektprofil

Das semantische Review prüft nicht jedes Projekt gleich. Ob ein Diff gegen
Mandantentrennung, Messenger-Wiederholungen oder Geldrundung geprüft werden
muss, hängt davon ab, was das Projekt überhaupt tut. Das hält das Profil fest.

Es liegt im Projekt unter **`.ai/guard-profile.yml`** und wird versioniert —
es beschreibt das Projekt, nicht einen einzelnen Lauf.

## Grundsatz: leer heißt unbekannt

Ein fehlender oder leerer Eintrag bedeutet **„unbekannt“**, nie „trifft nicht
zu“. Wer `mandanten` nicht ausfüllt, hat nicht erklärt, dass es keine Mandanten
gibt. Unbekanntes löst das Review selbst aus dem Code auf (siehe unten) und
nennt im Report, welche Annahmen es dabei getroffen hat.

Nur ein ausdrücklicher Wert schaltet eine Achse ab: `mandanten: keine`.

## Format

```yaml
version: 1

# webseite | webanwendung | api | cli
projekt_art: webanwendung

# formular | oidc | api_token | http_basic | keine — mehrere möglich
auth: [formular]

# keine | spalte | datenbank | schema
mandanten: spalte
# Nur bei mandanten != keine: woran der Mandant hängt
mandanten_feld: organisation
# Wo die Isolation zentral erzwungen wird (Doctrine-Filter, Voter, Repository-Basis)
mandanten_durchsetzung: src/Doctrine/OrganisationFilter.php

# Messenger-Transports mit asynchroner Verarbeitung; [] = keine
messenger: [async]

# Rechnet das Projekt mit Geldbeträgen?
geldbetraege: ja

# mysql | mariadb | postgresql | sqlite
datenbank: mariadb

# symfony-docker | managed-server | kubernetes
deployment: symfony-docker

# Pfade, die eine öffentliche API bilden (Vertrag mit Dritten)
oeffentliche_api: [/api/v1]

# Externe Dienste, an die geschrieben wird (Zahlung, Versand, Mail, Webhooks)
externe_dienste: [Stripe, DHL]

# Abläufe, deren Fehler Geld oder Kundendaten kosten
kritische_ablaeufe:
  - Bestellung abschließen
  - Zahlungseingang per Webhook

# Fachliche Invarianten, die nie verletzt werden dürfen
invarianten:
  - Eine Bestellnummer ist eindeutig.
  - Ein Kunde sieht nur Bestellungen seiner Organisation.

# Bewusste, begründete Ausnahmen. Regel-IDs wie im Report.
ausnahmen:
  - achse: injection
    pfad: src/Command/Migration/
    grund: Einmalige Import-Befehle, nur per CLI, Eingaben aus eigener Datei.
```

Alle Schlüssel sind optional. Ein Projekt ohne Profil ist erlaubt — dann ist
alles unbekannt.

## Welche Achse wann läuft

| Achse | läuft, wenn … | abgeschaltet nur durch |
|---|---|---|
| 1 Anforderungsdeckung | immer | — |
| 2 Erfundene Symbole | immer | — |
| 3 Autorisierung | `auth` ≠ `[keine]` | `auth: [keine]` |
| 4 Datenbank und Migration | der Diff Entities, Repositories oder Migrationen berührt | — |
| 5 Architektur | immer, nur gegen niedergeschriebene Regeln | — |
| 6 Mandantentrennung | `mandanten` ≠ `keine` | `mandanten: keine` |
| 7 Injection und Mass Assignment | der Diff Eingaben verarbeitet (Controller, Formulare, Deserializer, Commands, Message-Handler) | — |
| 8 Datenabfluss | der Diff Antworten, Serialisierung, Logs oder Fehlermeldungen berührt | — |

## Unbekanntes aus dem Code auflösen

Fehlt ein Wert, bestimme ihn — und nenne im Report die Quelle:

| Wert | Quelle |
|---|---|
| `auth` | `config/packages/security.yaml`: `form_login`, `json_login`, `http_basic`, `custom_authenticators`; OIDC an `access_token`/`oauth`/`oidc`-Konfiguration |
| `mandanten` | Entity-Felder oder Filter wie `tenant`, `organisation`, `mandant`, `company`, `client` an mindestens zwei Entities; Doctrine-SQL-Filter; eine Subdomain oder ein Routenparameter, der den Mandanten wählt |
| `messenger` | `config/packages/messenger.yaml`, `transports` mit `async` |
| `geldbetraege` | Felder `price`, `amount`, `total`, `betrag`, `preis`, `summe`, `netto`, `brutto`; `moneyphp/money` in `composer.lock` |
| `datenbank` | `DATABASE_URL` in `.env` |
| `deployment` | Includes in `.gitlab-ci.yml` (`symfony-docker/deploy.yml`, `managed-server`) |

Findest du Hinweise auf Mandanten, aber kein Profil, prüfe Achse 6 — im Zweifel
lieber prüfen als eine Lücke übersehen. Im Report steht dann: „Profil fehlt,
Mandantentrennung aus `src/Entity/…` abgeleitet“.

## Ausnahmen

Eine Ausnahme gilt nur mit Achse, Pfad **und** Grund. Trifft ein Befund auf eine
Ausnahme, wird er im Report unter „Bewusste Ausnahmen“ mit dem Grund geführt,
nicht verschwiegen und nicht gezählt. Eine Ausnahme ohne Grund ist ungültig.
