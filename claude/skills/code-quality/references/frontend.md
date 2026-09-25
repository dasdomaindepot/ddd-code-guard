# Frontend (Vue/JS)

## Ausgangslage

Über die Projekte hinweg gibt es **keine** make-Targets, die Frontend-Code
prüfen. `make assets` ist `assets:install` und kopiert Dateien, `make npm` ist
ein Docker-Build. Beide mutieren und sind für dich gesperrt.

In `package.json` finden sich Prüfskripte nur vereinzelt — in der Mehrzahl der
Projekte existieren `lint` und `typecheck` gar nicht.

**Damit ist die häufigste Erkenntnis dieses Bereichs die Lücke selbst.** Melde
sie als `MISSING` mit konkretem Vorschlag statt sie zu verschweigen; ein Projekt
mit Vue-Code und ohne jedes Frontend-Gate ist ein echter Befund.

## Erlaubte Checks

Nur diese drei, und nur wenn das Skript in `package.json` wirklich existiert:

- `npm run lint` — vorher das Skript lesen. Enthält es `--fix`, ist es gesperrt: `SKIPPED`.
- `npm run typecheck`
- `npm audit`

Gesperrt bleiben `npm install`, `npm ci`, `npm update`, `npm audit fix`,
`npm run build`, `npm run dev`, `watch` und jedes Skript, das schreibt oder
einen Server startet.

Läuft das Projekt seine Node-Werkzeuge ausschließlich im Container und
scheitert der Hostaufruf, ist der Check `BLOCKED` — baue keinen eigenen
`docker`-Aufruf.

## Bewertung

Melde bei ESLint Fehler und Warnungen getrennt, gruppiert nach Regel. Bei
`vue-tsc`/`tsc` die Fehlerzahl und ob `strict` aktiv ist — ein grüner Typecheck
ohne `strict` sagt wenig.

`npm audit` bewertest du wie `composer audit`: Schweregrad, direkt oder
transitiv. Behandle Advisories in reinen Build-Abhängigkeiten (`devDependencies`,
die nie ausgeliefert werden) nachrangig und sage dazu, warum.

## Vorschlag bei fehlendem Tooling

Nenne exakte Pakete, keine vagen Empfehlungen: `eslint` mit
`eslint-plugin-vue`, `vue-tsc` für Typprüfung, und ein `lint`-Skript in
`package.json`. Lege nichts davon an.
