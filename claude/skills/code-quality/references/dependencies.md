# Abhängigkeiten

Composer-Metadaten, Sicherheit, Lock-Konsistenz. Niemals `install`, `update`,
`require`, `remove`, `bump` — nichts, was das Lockfile neu schreibt.

## Erlaubte Checks

- `composer validate --strict` — Schema-, Lock- und Publish-Befunde getrennt bewerten
- `composer audit --locked` — bekannte Advisories gegen den gelockten Stand
- `composer outdated --direct` — nur auf Anfrage oder wenn es etwas erklärt
- `composer show <paket>` — gezielt, um einen installierten Stand zu deuten

Diese laufen auf dem Host, weil sie nur `composer.lock` lesen. Findet der
Host-Composer die PHP-Version nicht, weiche auf `make composer-*` aus, falls
das Projekt so ein Target hat, sonst `BLOCKED`.

## Bewertung

Melde je Advisory: Paket, betroffene installierte Version, Advisory-ID,
Schweregrad falls geliefert, und ob direkt oder transitiv. Aufgegebene
(`abandoned`) Pakete mit ihrem Nachfolger gehören in einen eigenen Block.

Prüfe die PHP- und Extension-Constraints sowie `config.platform`. Ein
Auseinanderlaufen von deklarierter Anforderung und laufender Umgebung ist eine
Warnung — ändere die Plattformkonfiguration nicht.

Trenne **Reproduzierbarkeitsprobleme** (ungültiges oder veraltetes Lockfile) von
bloßen **Update-Gelegenheiten**. Veraltet ist für sich genommen kein Mangel.
