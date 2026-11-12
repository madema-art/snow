// Renders the editable SVG sources in branding/ to PNG with headless Chromium
// (Playwright). Then run tools/make_icon.py to pack branding/snow.ico.
//   node tools/render_branding.js
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const dir = path.join(__dirname, '..', 'branding', 'source');
const out = path.join(__dirname, '..', 'branding');
(async () => {
  const browser = await chromium.launch();
  const jobs = [
    ['snow_icon.svg', path.join(dir, 'icon_1024.png'), 1024, 1024, true],
    ['snow_splash.svg', path.join(out, 'splash.png'), 1920, 1080, false],
  ];
  for (const [svg, png, w, h, transparent] of jobs) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    const markup = fs.readFileSync(path.join(dir, svg), 'utf8');
    await page.setContent(`<html><body style="margin:0;background:transparent">${markup}</body></html>`);
    await page.screenshot({ path: png, omitBackground: transparent, clip: { x: 0, y: 0, width: w, height: h } });
    await page.close();
    console.log('rendered', path.basename(png));
  }
  await browser.close();
})();
