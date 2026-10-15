'use strict';
const { chromium } = require('../tool/web_ocr/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
module.exports = async (browser, baseUrl, evidence) => {
  const results = [];
  const context = await browser.newContext({ locale: 'tr-TR', viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  // Expose the EXACT shipped geometry function for pixel diagnostics only.
  // The recognizer and all OCR outputs remain the real production implementation.
  await page.route('**/doku_ocr.js', async (route) => {
    const response = await route.fetch();
    const source = await response.text();
    await route.fulfill({
      response,
      body: source.replace(
        'globalThis.dokuOcr = Object.freeze',
        'globalThis.__dokuStraightenForTest = straightenLabel; globalThis.dokuOcr = Object.freeze',
      ),
    });
  });
  try {
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    for (const angle of [9, 12]) {
      const fixture = await page.evaluate((degrees) => {
        const c = document.createElement('canvas');
        c.width = 1200;
        c.height = 600;
        const g = c.getContext('2d');
        g.fillStyle = '#fff';
        g.fillRect(0, 0, c.width, c.height);
        g.save();
        g.translate(3, 65);
        g.rotate((degrees * Math.PI) / 180);
        g.font = 'bold 64px Arial';
        g.fillStyle = '#000';
        g.fillText('80% PAMUK', 0, 0);
        g.fillText('20% POLYESTER', 0, 125);
        g.restore();
        // Four corner markers must survive the same geometric operation.
        g.fillStyle = '#ff0000';
        for (const [x, y] of [
          [2, 2],
          [1190, 2],
          [2, 590],
          [1190, 590],
        ])
          g.fillRect(x, y, 8, 8);
        const png = c.toDataURL('image/png').split(',')[1];
        const detected = window.__dokuStraightenForTest(c);
        const rgba = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
        const corners = [0, 0, 0, 0];
        let red = 0;
        for (let i = 0; i < rgba.length; i += 4)
          if (rgba[i] > 180 && rgba[i + 1] < 80 && rgba[i + 2] < 80) {
            red++;
            const x = (i / 4) % c.width,
              y = Math.floor(i / 4 / c.width);
            corners[(y < c.height / 2 ? 0 : 2) + (x < c.width / 2 ? 0 : 1)]++;
          }
        return { png, detected, red, corners, width: c.width, height: c.height };
      }, angle);
      fs.writeFileSync(path.join(evidence, `edge-${angle}-source.png`), Buffer.from(fixture.png, 'base64'));
      const chooser = page.waitForEvent('filechooser');
      const picking = page.evaluate(() => {
        window.__edgePicking = window.dokuOcr.pick(false);
      });
      await picking;
      await (
        await chooser
      ).setFiles({ name: 'edge.png', mimeType: 'image/png', buffer: Buffer.from(fixture.png, 'base64') });
      await page.evaluate(async () => {
        window.__edgeSelected = await window.__edgePicking;
      });
      const output = await page.evaluate(() =>
        window.dokuOcr.recognizeSafe(window.__edgeSelected.path, () => {}),
      );
      results.push({
        angle,
        detected: fixture.detected,
        red: fixture.red,
        corners: fixture.corners,
        width: fixture.width,
        height: fixture.height,
        output,
      });
      fs.writeFileSync(path.join(evidence, 'edge-report.json'), JSON.stringify(results, null, 2));
      console.log('edge regression', JSON.stringify(results.at(-1)));
      assert.equal(output.code, null, 'Edge label remains reviewable');
      assert.match(output.text, /80\s*%\s*PAMUK/i, 'The source 80% PAMUK must survive real OCR');
      assert.match(output.text, /20\s*%\s*POLYESTER/i, 'The source 20% POLYESTER must survive real OCR');
      assert.ok(
        fixture.corners.every((count) => count >= 40),
        'Each original corner marker survives deskew',
      );
      assert.ok(Math.abs(fixture.detected) >= 2, 'The test actually exercised deskew');
      await page.evaluate(() => window.dokuOcr.release(window.__edgeSelected.path));
    }
  } finally {
    await context.close();
  }
};
if (require.main === module)
  (async () => {
    const evidence = path.resolve(process.env.OCR_EVIDENCE_DIR || 'build/web-ocr-edge-evidence');
    fs.mkdirSync(evidence, { recursive: true });
    const browser = await chromium.launch({
      headless: true,
      executablePath: process.env.CHROME_EXECUTABLE,
      args: ['--no-sandbox'],
    });
    try {
      await module.exports(browser, process.argv[2] || 'http://127.0.0.1:8083/etiket/', evidence);
    } finally {
      await browser.close();
    }
  })().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
