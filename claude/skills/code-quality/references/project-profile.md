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

# webseite | webanwendung | intern | api | cli
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

# Fremde Hosts, die beim ersten Seitenaufruf laden DÜRFEN (Check third-party).
# Hausstandard ist: nichts Fremdes vor einem Klick. Jede Freigabe braucht einen
# Grund, sonst zählt sie nicht.
externe_quellen:
  - host: js.zahlungsanbieter.example
    grund: Zahlungsformular muss laut Anbieter von dessen Server geladen werden.

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
  # Statt einer Achse kann eine Ausnahme auf eine Regel-ID zeigen:
  - regel: app-static/H8
    pfad: src/Legacy/
    grund: Altcode, wird mit dem Umbau Q1/2027 ersetzt.
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
| 9 Integrationen und Wiederholungen | der Diff externe Dienste, Webhooks oder Messenger-Handler berührt | — |
| 10 Fehlerbehandlung | der Diff `try`/`catch`, Fehlerpfade oder Fallbacks enthält | — |
| 11 Nebenläufigkeit und Datenintegrität | der Diff Schreibpfade berührt | — |

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

Bestehende Review-Ausnahmen mit `achse:` oder `regel:` bleiben gültig. Für die
Checks `form-protection`, `web-content`, `web-exposure` und `gate-integrity`
verwendet derselbe Abschnitt `check:` und optional `befund:`. Ohne `befund`
gilt der Eintrag für alle Befunde des Checks. `pfad:` bezeichnet bei Web-Checks
den URL-Pfad und bei Gate Integrity einen Dateipfad oder ein Verzeichnispräfix;
`muster:` ist alternativ ein Glob. Ohne beide Ziele gilt die Ausnahme für jeden
passenden Befund. `grund:` ist Pflicht: Fehlt er, erscheint „Ausnahme ohne
Begründung“ als eigener Befund. Unterdrückte Befunde erscheinen mit „bewusst
ausgenommen“ und Grund als Hinweis und zählen nicht für den Exit-Code.

`ablaufdatum: JJJJ-MM-TT` beendet die Ausnahme nach dem angegebenen Tag. Danach
erscheint der ursprüngliche Befund wieder und ein Hinweis „Ausnahme abgelaufen
seit …“. `nur_umgebung: dev` verlangt einen X-Debug-Token-Header oder die
Symfony-Toolbar in der lokalen Antwort. Bei `gate-integrity` ist dieses Feld
wirkungslos, da kein Webserver geprüft wird. Eine `Guard-Ausnahme:`-Commit-Zeile
funktioniert weiterhin.

```yaml
ausnahmen:
  - check: form-protection
    befund: honeypot
    pfad: /dev-login
    nur_umgebung: dev
    grund: Entwicklungsformular ist nur lokal erreichbar.
  - check: gate-integrity
    befund: G3
    pfad: config/reference.php
    grund: Von Symfony generierte Referenzdatei.
  - check: web-content
    befund: canonical
    muster: /hilfe/*
    ablaufdatum: 2027-12-31
    grund: Dokumentationsseiten werden später vereinheitlicht.
```

Ein internes Werkzeug hinter SSO kann so beschrieben werden:

```yaml
version: 1
projekt_art: intern
auth: [oidc]
ausnahmen: []
```

Bei `intern` entfallen SEO-Befunde (`web-content`: `meta-description`,
`canonical`, `h1`, `title-unique`, `description-unique`) und der gesamte
Formular-Spamschutz (`form-protection`) mit sichtbarem Hinweis. Barrierefreiheit
(darunter `title` als Seitentitel nach WCAG 2.4.2, `lang`, `label`, `main`,
Skip-Link) und Favicons bleiben aktiv. Der Profilentwurf schlägt
`intern` nur bei eindeutig geschützter Startseite und ausschließlicher OIDC-
Anmeldung vor.

### Befund-Schlüssel

| Check | Schlüssel |
|---|---|
| `form-protection` | `honeypot` |
| `web-content` | `lang`, `title`, `meta-description`, `canonical`, `viewport`, `viewport-zoom`, `h1`, `alt`, `alt-placeholder`, `accessible-name`, `label`, `duplicate-id`, `doctype`, `charset`, `charset-position`, `mixed-content`, `mixed-form`, `main`, `password-autocomplete`, `password-paste`, `json-ld`, `title-unique`, `description-unique` |
| `web-exposure` | `secret-file`, `http-status`, `stacktrace`, `cookie-flags`, `https-redirect`, `cors` |
| `gate-integrity` | `G1`, `G2`, `G3`, `G4`, `G5`, `G6`, `G7`, `G8` |

Für G3 verweist `pfad:` bei einem neuen `exclude-pattern` auf den ausgeschlossenen
Dateipfad, etwa `config/reference.php`. Für andere G3-Befunde gilt die
Konfigurationsdatei als Ziel.
