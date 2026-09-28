# ddd-code-guard

**Deterministic quality gates plus a semantic review for PHP/Symfony and Vue
projects — built for [Claude Code](https://claude.com/claude-code) and
[opencode](https://opencode.ai).**

[English](#english) · [Deutsch](#deutsch)

---

## English

### What it is

AI coding agents are fast, and they are confidently wrong about whether their
own work passes. `ddd-code-guard` takes that judgement away from the model:

1. **`code-guard`** — a plain Bash script (zero tokens). It detects which checks
   a project has, runs all of them in a fixed order and writes a
   machine-readable verdict to `docs/.guard/results.json`, plus one log per
   check. The exit code is the verdict.
2. **The `code-quality` skill and agent** — a read-only auditor that runs the
   script, then reviews the diff on the axes no tool covers: does it meet the
   requirement, does it invent services or ENV variables, is authorization
   enforced at object level, are migrations risky. Result:
   `docs/quality-report.md`, written so a coding agent can work through it.

The auditor **never changes project code**. Its only write target is the
report.

### Checks

`code-guard` discovers what exists and reports everything else as `MISSING`
rather than improvising:

| ID | What | Source |
|---|---|---|
| `composer-validate`, `composer-audit` | Composer metadata, known vulnerabilities | `composer` in the `php` container |
| `phpstan`, `phpcs`, `deptrac`, `lint` | Static analysis, coding standard, architecture rules, linters | `make` targets |
| `test`, `coverage`, `infection`, `e2e` | Tests, coverage, mutation testing, end-to-end | `make` targets |
| `npm-audit`, `npm-lint`, `npm-typecheck`, `npm-test`, `npm-build` | Frontend | `package.json` scripts |
| `web-hardening` | Security headers, robots.txt, sitemap, compression, cache headers of the running local instance | `bin/check-web-hardening` (advisory) |
| `app-static` | Config and source, no running instance: session cookie and CSRF settings, file uploads without `maxSize`/`mimeTypes`, `COPY .` without a `.dockerignore` excluding `.git` and `.env.local`; dangerous production config (`session_fixation_strategy: none`, profiler/debug bundle or a `require-dev` bundle enabled for all/prod, `APP_DEBUG=1` in production); hints for SQL built from variables, Twig `\|raw`, weak crypto, `eval`/`exec`, `outline: none` without `:focus-visible`, no `prefers-reduced-motion`, TypeScript without `strict` | `bin/check-app-static` (blocking, python3 + PyYAML) |
| `house-rules` | Rules learned in operation, no running instance. R1: phpcs ruleset that does not fit phpcs 4 (`exclude-pattern type="relative"` silently ignored, comma-separated array properties, Slevomat sniffs without `slevomat/coding-standard` installed); R2: no unescaped `$NAME` in `.env` values (Docker Compose interpolates and truncates silently); R3: `ENV TZ=Europe/Berlin` in the PHP Dockerfile plus a matching `date.timezone`; R4: `trusted_proxies` behind a reverse proxy plus nginx `real_ip_header` (no fixed CIDR/`private_ranges`, no `%env(default::…)%`, no `x-forwarded-host`/`-prefix`); R5: GitLab deploy jobs whose `needs` skip the test jobs | `bin/check-house-rules` (blocking, python3) |
| `symfony-lint` | Read-only Symfony self-checks in the running `php` container: `lint:container`, `lint:twig`, `lint:yaml --parse-tags`, Doctrine mapping, and schema drift when all migrations are applied (entity changed without a migration); pending local migrations are a hint | `bin/check-symfony-lint` (blocking, python3, running container) |
| `gate-integrity` | Diff against the base: lowered PHPStan level, more `ignoreErrors`/`excludePaths`, new baseline entries, weaker phpcs/PHPUnit config, new `@phpstan-ignore`/`phpcs:ignore`/`markTestSkipped`, `allow_failure` or a removed check job in `.gitlab-ci.yml`, `\|\| true` in Make recipes, new empty `catch` blocks; placeholders (`TODO`, `example.com`) are hints; a `Guard-Ausnahme: <reason>` line in a commit message downgrades everything to hints | `bin/check-gate-integrity` (blocking, python3 + git) |
| `migrations` | New migrations only, `up()` only: entities/repositories inside a migration, `DELETE`/`UPDATE` without `WHERE`, `NOT NULL` column without `DEFAULT` on PostgreSQL (hint on MySQL/MariaDB); hints for DROP/rename and irreversible `down()` | `bin/check-migrations` (blocking, python3 + git) |
| `secrets` | Tracked files only: committed `.env.local`/`.env.*.local` and gitleaks hits (local binary or an already pulled `zricethezav/gitleaks` image) are findings; `generic-api-key` hits and a real `APP_SECRET` in a committed `.env` are hints; exceptions via `.gitleaksignore`; secret values are never printed | `bin/check-secrets` (blocking, python3 + git) |
| `web-exposure` | Running local instance: no `.git`, `.env`, `composer.lock` or log files served (ASVS 13.4.1), unknown paths return 404 without stack trace, session cookies with Secure/HttpOnly/SameSite (ASVS 3.3.1), permanent http→https redirect, no CORS reflection with credentials | `bin/check-web-exposure` (blocking, python3) |
| `legal` | Outdated references in German legal pages (imprint, privacy policy, terms): TMG, RStV, TTDSG, EU ODR platform, Privacy Shield | `bin/check-legal` (advisory, python3) |
| `web-content` | HTML basics of the running local instance (home page plus sitemap URLs): `lang`, `<title>`, meta description, canonical, viewport without zoom lock, exactly one `<h1>`, `alt` on every image, no placeholder alt texts, links/buttons with an accessible name, labelled form fields, no duplicate ids, doctype, UTF-8 charset early, no mixed content, exactly one `<main>`, password fields usable by password managers, valid JSON-LD, unique titles and descriptions across pages; hints for missing skip link, heading jumps, missing `autocomplete` (description/canonical skipped on `noindex` pages; `hidden`/`aria-hidden` subtrees ignored) | `bin/check-web-content` (blocking, python3) |
| `auth-policy` | Login lockout after failed attempts (`login_throttling` or own rate limiter, BSI ORP.4.A13) password minimum length from `guard-policy.yml` (default 12) and a modern password hasher (no `plaintext`, `md5`, `sha1`, `sha256`/`sha512`, ASVS 11.4.2); `access_control` rules shadowed by an earlier, broader rule; hints for < 15 (NIST SP 800-63B-4), max < 64, missing `NotCompromisedPassword`, password change without the current password, SSO/OIDC | `bin/check-auth-policy` (blocking, python3 + PyYAML) |
| `form-protection` | Public POST forms (contact, registration, newsletter) of the running local instance need a honeypot or a captcha; honeypot-only is a hint recommending extra protection | `bin/check-form-protection` (blocking, python3) |
| `favicon` | Favicons of the running local instance: `/favicon.ico`, `<link rel="icon">`, every linked icon returns 200 with matching type and real size matching `sizes`, 180×180 apple-touch-icon, web manifest with 192×192 and 512×512 PNG icons; hints for missing SVG and maskable icons | `bin/check-favicon` (blocking, python3) |
| `web-resources` | Running local instance: broken internal links and images are findings; hints for images without `width`/`height`, images over 300 KB, JPEG/PNG without a WebP/AVIF alternative, external scripts without SRI or `async`/`defer`, redirect chains | `bin/check-web-resources` (blocking, python3) |
| `browser-audit` | `--full` only: axe-core against WCAG 2.2 A/AA in real Chrome (contrast, ARIA, JavaScript-rendered content); critical/serious block, the rest and all Lighthouse numbers (LCP, CLS, TBT, page weight) are hints | `bin/check-browser-audit` (blocking, node ≥ 22.19 + Chrome) |

To fix favicon findings, `bin/favicon-generate <logo> [project] [--name …] [--color #rrggbb]` builds the full icon set into `public/` with [RealFaviconGenerator](https://realfavicongenerator.net/) (npm `realfavicon`, runs locally) and prints the `<link>` tags for your layout. It is a helper, not a check: it never overwrites existing files without `--force` and never edits templates.

Expensive checks (coverage, infection, e2e, build) only run with `--full`.

### Assumptions

This grew out of one agency's project template, so it expects:

- a `Makefile` with targets such as `phpstan`, `phpcs`, `test`
- PHP running in a Docker Compose service called `php`
- optionally a local URL in `DOMAIN_NAME` (`.env.local`/`.env`) or
  `GUARD_WEB_URL` for the web-hardening, legal and web-content checks

Projects that differ still work — missing checks show up as `MISSING`.

Some texts (skill, agent, report) are in German. The report language follows
the skill; the checks themselves are language-neutral.

### Installation

```bash
git clone https://github.com/dasdomaindepot/ddd-code-guard.git
cd ddd-code-guard
./install.sh --dry-run   # show what would happen
./install.sh
```

`install.sh` symlinks instead of copying, so `git pull` is all you need to
update. Existing files are never deleted but moved to
`~/.claude-config-backups/<timestamp>/`.

| In the repo | Linked to |
|---|---|
| `claude/skills/code-quality/` | `~/.claude/skills/code-quality` |
| `claude/agents/code-quality.md` | `~/.claude/agents/code-quality.md` |
| `claude/commands/guard.md` | `~/.claude/commands/guard.md` |
| `opencode/agent/code-quality.md` | `~/.config/opencode/agent/code-quality.md` |

### Usage

```bash
# deterministic gates only
~/.claude/skills/code-quality/bin/code-guard
~/.claude/skills/code-quality/bin/code-guard --list          # inventory
~/.claude/skills/code-quality/bin/code-guard --full --boot   # everything, start Docker if needed
~/.claude/skills/code-quality/bin/code-guard --install-make  # add `make guard` to the Makefile
```

In Claude Code, `/guard` runs the full review through the `code-quality`
subagent and writes `docs/quality-report.md`.

Exit codes: `0` policy met · `1` policy violated · `2` usage error / no project
· `3` unexpected side effect in the worktree (stop and look) · `4` environment
did not start (`--boot`).

`docs/.guard/` hides itself from Git.

#### Weekly run

`bin/guard-weekly --project DIR` is meant for cron: it checks the worktree is
clean, prepares the development branch, runs `code-guard --boot`, lets an
agent (`opencode`, `claude` or `none`) write the report text and commits only
`docs/quality-report.md`. While a report is `open`, later runs leave it alone;
`guard-weekly --acknowledge` marks it done.

### Policy

Thresholds live in `claude/skills/code-quality/guard-policy.yml`.

### Contributing

Enable the pre-commit hook once per clone:

```bash
git config core.hooksPath .githooks
```

It runs `gitleaks` (local or via Docker) on staged changes and, if present, a
private denylist of regexes from `~/.config/ddd-code-guard/denylist`
(override with `DDD_GUARD_DENYLIST`) — handy for keeping customer names and
internal hostnames out of a public repo.

### License

MIT — see [LICENSE](LICENSE).

---

## Deutsch

### Was es ist

KI-Coding-Agenten sind schnell — und behaupten gern „grün", ohne dass es
stimmt. `ddd-code-guard` nimmt dem Modell dieses Urteil ab:

1. **`code-guard`** — ein reines Bash-Script (0 Tokens). Es erkennt, welche
   Prüfungen ein Projekt hat, fährt sie alle in fester Reihenfolge und schreibt
   ein maschinenlesbares Ergebnis nach `docs/.guard/results.json`, dazu ein Log
   je Check. Der Exit-Code ist das Verdikt.
2. **Der `code-quality`-Skill und -Agent** — ein rein lesender Auditor. Er fährt
   das Script und prüft danach den Diff auf den Achsen, die kein Werkzeug
   abdeckt: Anforderungsdeckung, erfundene Services oder ENV-Variablen,
   Autorisierung auf Objektebene, Migrationsrisiken. Ergebnis ist
   `docs/quality-report.md` — so geschrieben, dass ein Coding-Agent ihn
   abarbeiten kann.

Der Auditor **ändert nie Projektcode**. Seine einzige Schreibdatei ist der
Report.

### Prüfungen

`code-guard` erkennt, was vorhanden ist, und meldet alles andere als `MISSING`,
statt zu improvisieren. Die Tabelle oben im englischen Teil gilt unverändert:
Composer, PHPStan, phpcs, Deptrac, Linter, Tests, Coverage, Infection, E2E,
npm-Skripte, die Web-Härtung und die Rechtstexte (Impressum, Datenschutz, AGB)
der lokal laufenden Instanz. Teure Checks
laufen nur mit `--full`.

### Annahmen

Entstanden aus dem Projekt-Template einer Agentur, deshalb erwartet es:

- ein `Makefile` mit Targets wie `phpstan`, `phpcs`, `test`
- PHP in einem Docker-Compose-Service namens `php`
- optional eine lokale URL in `DOMAIN_NAME` (`.env.local`/`.env`) oder
  `GUARD_WEB_URL` für die Web-Härtung

Andere Projekte funktionieren auch — fehlende Prüfungen erscheinen als `MISSING`.

### Installation

```bash
git clone https://github.com/dasdomaindepot/ddd-code-guard.git
cd ddd-code-guard
./install.sh --dry-run   # zeigt, was passieren würde
./install.sh
```

`install.sh` verlinkt symbolisch statt zu kopieren — ein `git pull` genügt zum
Aktualisieren. Vorhandene Dateien werden nie gelöscht, sondern nach
`~/.claude-config-backups/<zeitstempel>/` verschoben.

### Benutzung

```bash
~/.claude/skills/code-quality/bin/code-guard                 # alle Gates
~/.claude/skills/code-quality/bin/code-guard --list          # Inventar
~/.claude/skills/code-quality/bin/code-guard --full --boot   # alles, Docker bei Bedarf starten
~/.claude/skills/code-quality/bin/code-guard --install-make  # `make guard` ins Makefile
```

In Claude Code startet `/guard` das volle Review über den
`code-quality`-Subagenten und schreibt `docs/quality-report.md`.

Exit-Codes: `0` Policy erfüllt · `1` Policy verletzt · `2` Nutzungsfehler /
kein Projekt · `3` unerwartete Nebenwirkung im Worktree (anhalten und
nachsehen) · `4` Umgebung ließ sich nicht starten (`--boot`).

Für den wöchentlichen Turnus per Cron gibt es `bin/guard-weekly` — Details im
englischen Teil und in `guard-weekly --help`.

### Mitentwickeln

Den Pre-Commit-Hook einmal pro Klon aktivieren:
`git config core.hooksPath .githooks`. Er fährt `gitleaks` und, falls vorhanden,
eine private Sperrliste aus `~/.config/ddd-code-guard/denylist` — damit
Kundennamen und interne Hosts nicht in einem öffentlichen Repo landen.

### Lizenz

MIT — siehe [LICENSE](LICENSE).
