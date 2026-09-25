# Symfony

Setzt `bin/console` und ein bootfähiges Projekt in einer Nicht-Produktivumgebung
voraus. Cache weder leeren noch vorwärmen.

## Weg

Die Symfony-Linter haben selten ein eigenes make-Target. Prüfe das
Makefile auf `lint`, `lint-yaml`, `lint-twig`, `lint-container`. Gibt es keins,
ist der Bereich `MISSING` — und genau das ist der wertvolle Befund: die
Linter sind billig und fehlen in der Gate-Kette.

Existiert ein Target, laufen darüber die anwendbaren Prüfungen:
`lint:container`, `lint:yaml`, `lint:twig`, `lint:xliff`.

## Doctrine

`doctrine:schema:validate` nur gegen eine nachweislich unkritische
Entwicklungs- oder Testverbindung. Rate nie, dass eine konfigurierte Datenbank
entbehrlich ist. Lässt sich die Sicherheit nicht belegen, überspringe die
Prüfung und schreibe in den Report, wie ein Mensch sie selbst sicher fahren kann.

Migrationen inspizierst du, führst sie aber nicht aus, erzeugst sie nicht,
diffst sie nicht und rollst sie nicht zurück. Halte fest, ob die CI einen
Migrationslauf auf frischer Datenbank testet — lege ihn nicht an.

## Deprecations

Nur über einen bereits konfigurierten, nicht-mutierenden Weg. Trenne
Framework-/Vendor-Deprecations von solchen der Anwendung.

Ein Boot-Fehler ist ein gescheiterter Umgebungs-Check — kein Beleg dafür, dass
jede einzelne Lint-Kategorie durchgefallen wäre.
