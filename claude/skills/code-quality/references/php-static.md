# Statische Analyse und Coding-Standard

## PHPStan — `make phpstan`

Das Target fährt intern `docker compose exec php ./vendor/bin/phpstan analyse`
mit der Projektkonfiguration. Nimm die Konfiguration wie sie ist, setze keine
eigenen Pfade und keine Report-Flags.

Melde: Fehlerzahl, das effektive Level, ob eine Baseline im Spiel ist, welche
Extensions (Symfony, Doctrine) geladen sind.

Eine Baseline ist für sich kein Mangel. Melde ihre Existenz, ihren ungefähren
Umfang wenn billig messbar, und ob sie neue Fehler blockiert. **Warne**, wenn
PHPStan auf niedrigem Level läuft, nur einen schmalen Pfad scannt oder große
Produktivbereiche still ausschließt — ein grünes PHPStan auf Level 1 über zwei
Verzeichnisse ist kein Qualitätsnachweis.

## Coding-Standard — `make phpcs`

Reine Inspektion. `make phpcbf` existiert in manchen Projekten und ist für dich
gesperrt — es korrigiert.

Melde Zahl der betroffenen Dateien und Verstöße, gruppiert nach Sniff.

## Rector

Nur wenn ein make-Target existiert **und** es nachweislich `--dry-run` fährt.
Lies das Target, bevor du es aufrufst. Ohne diesen Nachweis: `SKIPPED` mit
Begründung. Melde die vorgeschlagenen Dateien und Regeln, wende nichts an.

## Darstellung

Zu jedem Befund gehören Pfad und Zeile, sobald das Werkzeug sie liefert.
Gleichartige Befunde fasst du nach Regel zusammen und zeigst repräsentative
Stellen — der Report ist eine Entscheidungsgrundlage, keine Logablage.
