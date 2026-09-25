# Tests

## `make test` verändert Zustand — das ist eingeplant

In den Projekten sieht das Target typischerweise so aus:

    test:
        $(MAKE) init-test-db     # docker compose up php + doctrine:migrations:migrate (APP_ENV=test)
        $(PHP_BASH) 'php vendor/bin/phpunit --testsuite "Project Test Suite"'

Es startet also Container und migriert die **Test**-Datenbank. Das ist auf dem
Entwicklerrechner freigegeben und der einzige Weg, die Suite überhaupt zu fahren.

Zwei Pflichten daraus:

1. Lies das Target, bevor du es startest. Migriert es etwas anderes als
   `APP_ENV=test`, oder hängt eine Fixture-Ladung daran, führe es nicht aus —
   `SKIPPED`, mit dem gelesenen Befehl als Begründung.
2. Der Report nennt unter *Nebenwirkungen*, welche Container liefen und dass die
   Test-Datenbank migriert wurde. Das ist keine Worktree-Verletzung — die
   Baseline-Prüfung bezieht sich allein auf `git status`.

## PHPUnit

Fahre die normale Projektkonfiguration. Keine Snapshot-Aktualisierung, keine
Ausgabedateien, keine zusätzlichen Coverage-Flags — `make coverage` existiert in
vielen Projekten und ist ein eigenes, freigegebenes Target, wenn Coverage
verlangt ist.

Melde getrennt: Tests, Assertions, Failures, Errors, Skipped, Incomplete, Risky,
Deprecations, Warnings.

Eine grüne Suite mit riskanten, unvollständigen oder unerwartet übersprungenen
Tests ist mindestens `WARN` — es sei denn, das Projekt akzeptiert sie erklärt.

## Infection

Zuletzt, und nur wenn Mutation-Testing ausdrücklich verlangt ist, der Audit als
umfassend angefordert wurde oder `make infection` erkennbar zur normalen
Gate-Kette des Projekts gehört. Sonst `SKIPPED` mit Grund — es ist teuer.

Melde MSI, Covered-Code-MSI, entkommene Mutanten, Fehler/Timeouts, konfigurierte
Schwellen und ob sie gehalten haben. Trenne schwache Assertions von äquivalenten
oder nicht abgedeckten Mutanten. Empfiehl niemals, Tests zu löschen, um den
Score zu heben.

## Schwellen

Fehlt eine Coverage- oder Mutationsschwelle, melde den gemessenen Wert als
Information und schlage eine **Ratsche** auf genau diesem Wert vor. Erfinde
keine allgemeingültige Zielmarke.
