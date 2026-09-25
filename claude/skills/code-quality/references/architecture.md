# Architektur

Ausführbare Regeln schlagen subjektive Stilmeinungen.

## Deptrac

Nur über ein make-Target. Melde getrennt: Verstöße, übersprungene Verstöße,
nicht abgedeckte Abhängigkeiten, Konfigurations- oder Collector-Fehler.

Eine Architekturprüfung ist **nicht** sauber, wenn eine breite Skip-Liste oder
eine Baseline die Verstöße verdeckt. Fasse die wichtigen erlaubten
Schichtrichtungen und die folgenreichsten verbotenen Abhängigkeiten zusammen.

## Architekturtests

Suche sie über Suite, Group, Verzeichnis oder Namenskonvention und fahre sie
nur über ein freigegebenes Test-Target.

## Konventionen ohne Durchsetzung

Regeln, die nur in `CLAUDE.md`, `AGENTS.md` oder `docs/` stehen, kennzeichnest
du als `DOKUMENTIERT` — niemals als `DURCHGESETZT`.

## Signale

Domain hängt an Symfony/Doctrine-Infrastruktur; Controller tragen Geschäftslogik;
modulübergreifender Zugriff auf Internas; direkter Service-Locator; veränderliche
Zeitobjekte wo verboten; direkter Zugriff auf Umgebungsvariablen; HTTP-Clients
außerhalb der Infrastruktur.

Das sind **Kandidaten**, solange keine konfigurierte Regel oder ein präziser
Codebeleg sie zu bewiesenen Verstößen macht. Kennzeichne den Unterschied.

## Hausregeln

Diese gelten projektübergreifend. Kein Werkzeug prüft sie — **du suchst sie
selbst mit `grep`**, in jedem Audit, und zwar in beiden Fällen:

1. **`empty()` ist verboten.** Grep nach `empty(` in Produktivcode. Richtig sind
   `=== null`, `=== ''`, `=== []`, `count() === 0`. Jeder Treffer ist ein
   bewiesener Verstoß mit Datei und Zeile.

2. **Deutsche Texte tragen Umlaute und `ß`.** Grep nach `fuer`, `ueber`,
   `Strasse`, `gemaess`, `Koeln`, `loeschen`, `groesse`, `Geschaeft`, `Reiss`
   in Templates, Übersetzungsdateien, UI-Strings und Kommentaren. Ein Treffer
   ist ein Befund — `ae/oe/ue/ss` statt `ä/ö/ü/ß` wirkt unprofessionell.
   Technische Bezeichner (Variablen, Dateinamen, Branches) sind ausgenommen.

Beide Suchen gehören in jeden Lauf, auch wenn alle Werkzeuge grün melden.
