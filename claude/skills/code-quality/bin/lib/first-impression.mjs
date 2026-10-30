// Zwei Screenshots des ersten Bildschirms mit playwright-core aus dem Browser-Cache.
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';

const [url, target] = process.argv.slice(2);
const require = createRequire(path.join(process.env.GUARD_BROWSER_DEPS, 'package.json'));
const { chromium } = require('playwright-core');
const browser = await chromium.launch({ executablePath: process.env.GUARD_CHROME, headless: true, args: ['--no-sandbox'] });
try {
  for (const [name, viewport, mobile] of [
    ['desktop', { width: 1366, height: 768 }, false],
    ['mobil', { width: 390, height: 844 }, true],
  ]) {
    const context = await browser.newContext({
      viewport,
      deviceScaleFactor: mobile ? 2 : 1,
      isMobile: mobile,
      hasTouch: mobile,
      userAgent: mobile ? 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36' : undefined,
      ignoreHTTPSErrors: true,
    });
    try {
      const page = await context.newPage();
      const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
      if (!response || response.status() !== 200) throw new Error(`${name}: Startseite liefert HTTP ${response?.status() ?? 'keinen Status'}`);
      const png = path.join(target, `${name}.png`);
      await page.screenshot({ path: png, fullPage: false });
      if (fs.statSync(png).size > 900000) {
        fs.unlinkSync(png);
        const jpeg = path.join(target, `${name}.jpg`);
        for (const quality of [75, 55, 35]) {
          await page.screenshot({ path: jpeg, type: 'jpeg', quality, fullPage: false });
          if (fs.statSync(jpeg).size <= 900000) break;
        }
        if (fs.statSync(jpeg).size > 900000) throw new Error(`${name}: Bild bleibt über 900 KiB`);
      }
    } finally {
      await context.close();
    }
  }
} finally {
  await browser.close();
}
