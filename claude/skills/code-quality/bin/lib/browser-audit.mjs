// browser-audit.mjs — Barrierefreiheit (axe-core) und Ladeverhalten (Lighthouse)
// einer lokal laufenden Instanz im echten Browser prüfen.
//
// Wird von bin/check-browser-audit aufgerufen, das die Abhängigkeiten in einen
// Cache-Ordner installiert und dessen Pfad als GUARD_BROWSER_DEPS übergibt:
//   node browser-audit.mjs <https://lokale-url>
//
// Ausgabe im Stil der übrigen Checks (BEFUND / ok / Hinweis), Exit-Codes:
//   0 keine Befunde · 1 Befunde · 2 Nutzungsfehler · 77 nicht messbar

import { createRequire } from 'node:module';
import path from 'node:path';

const deps = process.env.GUARD_BROWSER_DEPS;
const chromePath = process.env.GUARD_CHROME;
const maxPages = Number.parseInt(process.env.MAX_PAGES ?? '10', 10) || 10;
const require = createRequire(path.join(deps ?? '.', 'package.json'));

let findings = 0;
const finding = (m) => { findings += 1; console.log(`BEFUND   ${m}`); };
const ok = (m) => console.log(`ok       ${m}`);
const hint = (m) => console.log(`Hinweis  ${m}`);

const base = (process.argv[2] ?? '').replace(/\/+$/, '');
if (!base || !deps || !chromePath) {
  console.error('Verwendung: GUARD_BROWSER_DEPS=… GUARD_CHROME=… node browser-audit.mjs <https://lokale-url>');
  process.exit(2);
}

const { chromium } = require('playwright-core');
const axeSource = require('fs').readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');

// Seiten wie bei den übrigen Checks: Startseite plus Sitemap, Host der Sitemap
// wegwerfen (sie nennt oft den Produktions-Host), gemessen wird lokal.
async function collectPaths(context) {
  const paths = ['/'];
  try {
    const res = await context.request.get(`${base}/sitemap.xml`, { timeout: 15000 });
    if (res.ok()) {
      const xml = await res.text();
      if (!/<sitemapindex/i.test(xml)) {
        for (const m of xml.matchAll(/<loc>\s*([^<]+?)\s*<\/loc>/g)) {
          const p = new URL(m[1]).pathname || '/';
          if (!paths.includes(p)) paths.push(p);
        }
      }
    }
  } catch { /* keine Sitemap: nur die Startseite */ }
  if (paths.length > maxPages) hint(`${maxPages} von ${paths.length} Seiten im Browser geprüft (MAX_PAGES)`);
  return paths.slice(0, maxPages);
}

// axe-core: WCAG 2.0–2.2 Stufe A und AA. "critical"/"serious" sind Befunde,
// "moderate"/"minor" Hinweise. Die Symfony-Toolbar gehört nicht zur App.
async function axeAudit(context, paths) {
  const byRule = new Map();
  let measured = 0;
  for (const p of paths) {
    const page = await context.newPage();
    try {
      const res = await page.goto(base + p, { waitUntil: 'networkidle', timeout: 30000 });
      if (!res || res.status() !== 200) { await page.close(); continue; }
      await page.addScriptTag({ content: axeSource });
      const result = await page.evaluate(async () => {
        // eslint-disable-next-line no-undef
        return axe.run(
          { exclude: [['.sf-toolbar'], ['[id^="sfwdt"]'], ['[id^="sfToolbar"]']] },
          { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] } },
        );
      });
      measured += 1;
      for (const v of result.violations) {
        const entry = byRule.get(v.id) ?? { impact: v.impact, help: v.help, pages: new Set(), nodes: 0, example: '' };
        entry.pages.add(p);
        entry.nodes += v.nodes.length;
        if (!entry.example && v.nodes[0]) entry.example = v.nodes[0].target.join(' ');
        byRule.set(v.id, entry);
      }
    } catch (e) {
      hint(`${p}: im Browser nicht prüfbar (${String(e.message).split('\n')[0]})`);
    }
    await page.close();
  }
  if (measured === 0) return false;
  const order = { critical: 0, serious: 1, moderate: 2, minor: 3 };
  const rules = [...byRule.entries()].sort((a, b) => order[a[1].impact] - order[b[1].impact]);
  for (const [id, e] of rules) {
    const pages = [...e.pages];
    const where = pages.slice(0, 3).join(', ') + (pages.length > 3 ? ` (+${pages.length - 3})` : '');
    const text = `axe ${id} (${e.impact}): ${e.help} — ${e.nodes}× auf ${where}, z. B. ${e.example}`;
    if (e.impact === 'critical' || e.impact === 'serious') finding(text); else hint(text);
  }
  if (rules.length === 0) ok(`axe-core: ${measured} Seite(n) ohne WCAG-2.2-AA-Verstöße`);
  return true;
}

// Lighthouse nur auf der Startseite und nur als Hinweis: Lokale Messwerte hängen
// an Rechner und Dev-Modus und sind kein belastbares Urteil über die Produktion.
async function lighthouseAudit(port) {
  const { default: lighthouse } = await import(require.resolve('lighthouse'));
  const res = await lighthouse(`${base}/`, {
    port, output: 'json', logLevel: 'error',
    onlyCategories: ['performance', 'best-practices', 'seo'],
    formFactor: 'mobile',
  });
  const lhr = res?.lhr;
  if (!lhr) { hint('Lighthouse lieferte kein Ergebnis'); return; }
  const score = (c) => Math.round((lhr.categories[c]?.score ?? 0) * 100);
  const a = lhr.audits;
  const lcp = a['largest-contentful-paint']?.numericValue;
  const cls = a['cumulative-layout-shift']?.numericValue;
  const tbt = a['total-blocking-time']?.numericValue;
  const weight = a['total-byte-weight']?.numericValue;
  const line = `Lighthouse (lokal, mobil): Performance ${score('performance')}, Best Practices ${score('best-practices')}, SEO ${score('seo')}`
    + ` · LCP ${(lcp / 1000).toFixed(1)} s · CLS ${cls?.toFixed(2)} · TBT ${Math.round(tbt)} ms · ${Math.round(weight / 1024)} KB`;
  if (lcp > 2500 || cls > 0.1 || tbt > 600 || weight > 3 * 1024 * 1024) hint(line); else ok(line);
  if (lcp > 2500) hint(`LCP ${(lcp / 1000).toFixed(1)} s über 2,5 s — größtes Element (meist Bild) früher/kleiner laden`);
  if (cls > 0.1) hint(`CLS ${cls.toFixed(2)} über 0,1 — Bildern und Einbettungen feste Maße geben`);
  if (weight > 3 * 1024 * 1024) hint(`Startseite überträgt ${Math.round(weight / 1024)} KB — über 3 MB`);
}

const port = 9222 + Math.floor(Math.random() * 500);
let browser;
try {
  browser = await chromium.launch({
    executablePath: chromePath, headless: true,
    args: [`--remote-debugging-port=${port}`, '--ignore-certificate-errors'],
  });
} catch (e) {
  console.log(`Chrome startet nicht (${String(e.message).split('\n')[0]}) — nicht messbar.`);
  process.exit(77);
}
try {
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  const start = await context.request.get(`${base}/`, { timeout: 15000 }).catch(() => null);
  if (!start || start.status() !== 200) {
    console.log(`Startseite ${base}/ liefert HTTP ${start ? start.status() : 0} — Instanz läuft nicht oder ist nicht die App.`);
    await browser.close();
    process.exit(77);
  }
  const paths = await collectPaths(context);
  const measured = await axeAudit(context, paths);
  if (!measured) {
    console.log('Keine Seite im Browser messbar — nicht messbar.');
    await browser.close();
    process.exit(77);
  }
  if (process.env.GUARD_SKIP_LIGHTHOUSE !== '1') {
    try { await lighthouseAudit(port); } catch (e) { hint(`Lighthouse fehlgeschlagen: ${String(e.message).split('\n')[0]}`); }
  }
} finally {
  await browser?.close();
}

console.log('');
if (findings > 0) { console.log(`${findings} Befund(e).`); process.exit(1); }
console.log('Keine Befunde.');
process.exit(0);
