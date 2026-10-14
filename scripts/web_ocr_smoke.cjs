'use strict';
const {chromium} = require('../tool/web_ocr/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const baseUrl = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
const evidence = path.resolve(process.env.OCR_EVIDENCE_DIR || 'build/web-ocr-evidence');
fs.mkdirSync(evidence, {recursive: true});
(async () => {
  const browser = await chromium.launch({headless: true,
    ...(process.env.CHROME_EXECUTABLE ? {executablePath: process.env.CHROME_EXECUTABLE} : {}),
    args: ['--no-sandbox']});
  const report = [];
  try {
    for (const width of [360, 390, 430, 1280]) {
      const mobile = width < 500;
      const context = await browser.newContext({viewport: {width, height: 900}, isMobile: mobile, hasTouch: mobile,
        ...(mobile ? {userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36'} : {})});
      const page = await context.newPage();
      const errors = [], failures = [], requests = [], responses = [];
      page.on('pageerror', e => errors.push(e.message));
      page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
      page.on('requestfailed', request => failures.push(request.url()));
      page.on('request', request => {
        requests.push({url: request.url(), method: request.method()});
        assert.ok(['GET', 'HEAD'].includes(request.method()), 'No image/text upload requests');
      });
      page.on('response', response => { if (response.url().includes('/ocr/')) responses.push({url: response.url(), status: response.status()}); });
      const button = async name => {
        const target = page.getByRole('button', {name, exact: true});
        for (let i = 0; i < 12 && await target.count() === 0; i++) {
          await page.mouse.move(width / 2, 650); await page.mouse.wheel(0, 450); await page.waitForTimeout(100);
        }
        await target.click();
      };
      const seen = async text => page.getByText(text).or(page.locator(`[aria-label*="${text}"]`)).first().waitFor({timeout: 120000});
      await page.goto(baseUrl, {waitUntil: 'networkidle'});
      const semantics = page.locator('flt-semantics-placeholder');
      if (mobile) await semantics.click({force: true});
      else await semantics.evaluate(el => el.click());
      await page.getByRole('button', {name: 'Etiket tara', exact: true}).waitFor();
      const fixture = await page.evaluate(() => {
        const canvas = document.createElement('canvas'); canvas.width = 1200; canvas.height = 800;
        const ctx = canvas.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 1200, 800);
        ctx.fillStyle = '#000'; ctx.font = 'bold 56px Arial';
        ['DIŞ KUMAŞ / SHELL', '70% PAMUK / COTTON', '30% POLYESTER', 'ASTAR / LINING', '100% VİSKON / VISCOSE'].forEach((line, i) => ctx.fillText(line, 70, 120 + i * 130));
        return canvas.toDataURL('image/png').split(',')[1];
      });
      const fixturePath = path.join(evidence, 'synthetic-label.png');
      fs.writeFileSync(fixturePath, Buffer.from(fixture, 'base64'));
      await button('Etiket tara');
      await page.getByRole('button', {name: 'Fotoğraf yükle / galeriden seç', exact: true}).waitFor();
      assert.equal(await page.getByRole('button', {name: 'Fotoğraf çek', exact: true}).count(), mobile ? 1 : 0);
      const upload = async (source = 'Fotoğraf yükle / galeriden seç') => {
        const chooser = page.waitForEvent('filechooser');
        await button(source);
        const selected = await chooser;
        await selected.setFiles(fixturePath);
        // Flutter's off-screen image semantics appear only after scrolling.
        // The enabled OCR button below the preview proves acquisition completed.
      };
      await upload(mobile && width === 390 ? 'Fotoğraf çek' : undefined);
      assert.equal(await page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true}).count(), 0);
      await button('Fotoğraftaki metni oku');
      const review = page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true});
      for (let i = 0; i < 240 && await review.count() === 0; i++) {
        await page.mouse.move(width / 2, 650); await page.mouse.wheel(0, 120);
        await page.waitForTimeout(500);
      }
      await review.click();
      const field = page.getByRole('textbox', {name: /Etiket metni/});
      // Flutter attaches its editing client/value when this semantic field gains focus.
      await field.click();
      await page.waitForTimeout(100);
      const raw = await field.inputValue();
      fs.writeFileSync(path.join(evidence, `raw-${width}.txt`), raw);
      await page.screenshot({path: path.join(evidence, `raw-${width}.png`)});
      assert.match(raw, /70%\s+PAMUK/i); assert.match(raw, /30%\s+POLYESTER/i); assert.match(raw, /100%\s+V[İI]SKON/i);
      // Correct the raw proposal explicitly. No inferred OCR correction.
      await field.fill('Dış kumaş\n80% Pamuk\n20% Polyester\nAstar\n100% Viskon');
      await button('Metni ayrıştır'); await button('Düzenleyicide incele');
      const proceed = page.getByRole('button', {name: 'Devam et', exact: true});
      assert.equal(await proceed.isEnabled(), false);
      const confirmation = page.getByRole('checkbox', {name: 'Etiketle karşılaştırdım ve doğruladım', exact: true});
      if (mobile) await confirmation.tap(); else await confirmation.click();
      await page.locator('[role="checkbox"][aria-checked="true"]').waitFor();
      assert.equal(await proceed.isEnabled(), true);
      await proceed.click(); await button('Analizi göster');
      await seen('Pamuk %80 · Polyester %20'); await seen('Viskon %100');
      await page.screenshot({path: path.join(evidence, `result-${width}.png`)});
      for (const fragment of ['worker.min.js', '/core/tesseract-core-', '/lang/tur.traineddata.gz', '/lang/eng.traineddata.gz']) {
        assert.ok(responses.some(r => r.url.includes(fragment) && r.status === 200), `Loaded ${fragment} under /etiket/`);
      }
      assert.ok(responses.every(r => r.status === 200));
      for (const variant of ['lstm', 'simd-lstm']) {
        const url = new URL(`ocr/core/tesseract-core-${variant}.wasm`, baseUrl).href;
        const response = await page.request.head(url);
        assert.equal(response.status(), 200);
        assert.match(response.headers()['content-type'], /application\/wasm/);
      }
      assert.ok(requests.filter(r => r.url.includes('/ocr/')).every(r => r.url.startsWith(new URL('ocr/', baseUrl).href)));
      assert.deepEqual(failures, []); assert.deepEqual(errors, []);
      report.push({width, raw, assets: responses, errors, failures, captureChooser: width === 390});
      console.log(`PASS ${width}dp: real TR/EN OCR, local /etiket/ assets, editable raw text, separate sections, required approval, no console/network errors.`);
      await context.close();
    }
    fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2));
    await require('./web_ocr_safety.cjs')(browser, baseUrl, evidence);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
