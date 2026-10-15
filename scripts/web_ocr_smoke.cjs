'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const baseUrl = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
const evidence = path.resolve(process.env.OCR_EVIDENCE_DIR || 'build/web-ocr-evidence');
fs.mkdirSync(evidence, {recursive: true});
let stage = 'load browser driver';
let diagnosticErrors = [], diagnosticFailures = [], diagnosticResponses = [], diagnosticWarnings = [];
(async () => {
  const {chromium} = require('../tool/web_ocr/node_modules/playwright');
  stage = 'launch Chromium';
  const browser = await chromium.launch({headless: true,
    ...(process.env.CHROME_EXECUTABLE ? {executablePath: process.env.CHROME_EXECUTABLE} : {}),
    args: ['--no-sandbox']});
  const report = [];
  try {
    stage = 'wait for static server';
    for (let attempt = 0; ; attempt++) {
      try { assert.equal((await fetch(baseUrl)).status, 200); break; }
      catch (error) {
        if (attempt === 49) throw error;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }
    for (const width of [360, 390, 430, 1280]) {
      stage = `${width}: open compiled app`;
      const mobile = width < 500;
      const context = await browser.newContext({locale: 'tr-TR', viewport: {width, height: 900}, isMobile: mobile, hasTouch: mobile,
        ...(mobile ? {userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36'} : {})});
      const page = await context.newPage();
      const errors = [], failures = [], requests = [], responses = [];
      diagnosticErrors = errors; diagnosticFailures = failures;
      diagnosticResponses = []; diagnosticWarnings = [];
      page.on('pageerror', e => errors.push(e.message));
      page.on('console', message => {
        if (message.type() === 'error') errors.push(message.text());
        if (message.type() === 'warning' && diagnosticWarnings.length < 20) diagnosticWarnings.push(message.text());
      });
      page.on('requestfailed', request => failures.push(request.url()));
      page.on('request', request => {
        requests.push({url: request.url(), method: request.method()});
        assert.ok(['GET', 'HEAD'].includes(request.method()), 'No image/text upload requests');
      });
      page.on('response', response => {
        diagnosticResponses.push({url: response.url(), status: response.status()});
        if (response.url().includes('/ocr/')) responses.push({url: response.url(), status: response.status()});
      });
      const button = async name => {
        const target = page.getByRole('button', {name, exact: true});
        for (let i = 0; i < 12 && await target.count() === 0; i++) {
          await page.mouse.move(width / 2, 650); await page.mouse.wheel(0, 450); await page.waitForTimeout(100);
        }
        await target.click();
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      };
      const seen = async text => page.getByText(text).or(page.locator(`[aria-label*="${text}"]`)).first().waitFor({timeout: 120000});
      await page.goto(baseUrl, {waitUntil: 'networkidle'});
      stage = `${width}: enable accessibility`;
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
      stage = `${width}: select label image`;
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
      stage = `${width}: wait for real OCR`;
      const review = page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true});
      for (let i = 0; i < 240 && await review.count() === 0; i++) {
        await page.mouse.move(width / 2, 650); await page.mouse.wheel(0, 120);
        await page.waitForTimeout(500);
      }
      await review.click();
      stage = `${width}: read editable raw text`;
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
      stage = `${width}: parse, validate sections and confirm`;
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
    // A realistic angled fabric-tag photo must preserve every printed percentage.
    // This was not covered by the original large, perfectly horizontal demo.
    stage = 'angled textile photo OCR';
    {
      const context = await browser.newContext({locale: 'tr-TR', viewport: {width: 390, height: 844},
        isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36'});
      const page = await context.newPage();
      try {
        await page.goto(baseUrl, {waitUntil: 'networkidle'});
        await page.locator('flt-semantics-placeholder').click({force: true});
        const fixture = await page.evaluate(() => {
          const canvas = document.createElement('canvas');
          canvas.width = 850; canvas.height = 900;
          const g = canvas.getContext('2d');
          g.fillStyle = '#d9d6cb'; g.fillRect(0, 0, 850, 900);
          g.translate(425, 450); g.rotate(-9 * Math.PI / 180);
          g.fillStyle = '#eee9dc'; g.fillRect(-310, -260, 620, 520);
          g.strokeStyle = '#a9a496'; g.lineWidth = 3; g.strokeRect(-310, -260, 620, 520);
          g.fillStyle = '#57534d'; g.font = '20px Arial';
          ['DIŞ KUMAŞ / SHELL', '80% PAMUK / COTTON', '20% POLYESTER',
            'ASTAR / LINING', '100% VİSKON / VISCOSE'].forEach((line, i) => g.fillText(line, -280, -180 + i * 85));
          return canvas.toDataURL('image/png').split(',')[1];
        });
        const fixturePath = path.join(evidence, 'angled-label.png');
        fs.writeFileSync(fixturePath, Buffer.from(fixture, 'base64'));
        await page.getByRole('button', {name: 'Etiket tara', exact: true}).click();
        const chooser = page.waitForEvent('filechooser');
        await page.getByRole('button', {name: 'Fotoğraf yükle / galeriden seç', exact: true}).click();
        await (await chooser).setFiles(fixturePath);
        await page.getByRole('button', {name: 'Fotoğraftaki metni oku', exact: true}).click();
        await page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true}).waitFor({timeout: 120000});
        await page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true}).click();
        const field = page.getByRole('textbox', {name: /Etiket metni/});
        await field.click();
        await page.waitForTimeout(150); // Flutter attaches the editing value after focus.
        const raw = await field.inputValue();
        fs.writeFileSync(path.join(evidence, 'angled-raw.txt'), raw);
        console.log('Synthetic angled-tag raw OCR:', JSON.stringify(raw));
        await page.screenshot({path: path.join(evidence, 'angled-raw.png')});
        assert.match(raw, /80\s*%\s*PAMUK/i, '80% PAMUK on a tilted label');
        assert.match(raw, /20\s*%\s*POLYESTER/i, '20% POLYESTER on a tilted label');
        assert.match(raw, /100\s*%\s*V[İI]SKON/i, '100% VISKON on a tilted label');
        console.log('PASS angled textile label: printed 80%, 20%, and 100% preserved by real OCR.');
      } finally { await context.close(); }
    }
    // Verify against the REAL WebAssembly recognizer, not a fake service or
    // Flutter's lazily exposed off-screen semantics tree.
    for (const pattern of ['blank', 'woven']) {
      stage = `reject no-text ${pattern} image`;
      const context = await browser.newContext({locale: 'tr-TR', viewport: {width: 390, height: 844},
        isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36'});
      const page = await context.newPage();
      try {
        await page.goto(baseUrl, {waitUntil: 'networkidle'});
        await page.locator('flt-semantics-placeholder').click({force: true});
        // Intercept only local image blob URL creation, never any image content or
        // user data; these fixtures contain no letters or sensitive material.
        await page.evaluate(() => {
          const original = URL.createObjectURL.bind(URL);
          URL.createObjectURL = blob => {
            const url = original(blob);
            if (blob.type?.startsWith('image/')) window.__dokuSyntheticPhoto = url;
            return url;
          };
        });
        const png = await page.evaluate(kind => {
          const canvas = document.createElement('canvas');
          canvas.width = 900; canvas.height = 900;
          const g = canvas.getContext('2d');
          g.fillStyle = kind === 'blank' ? '#deddd8' : '#b2b0a5';
          g.fillRect(0, 0, 900, 900);
          if (kind === 'woven') {
            for (let y = 0; y < 900; y += 7) {
              g.strokeStyle = y % 14 === 0 ? '#77766e' : '#a09e94';
              g.lineWidth = 2; g.beginPath(); g.moveTo(0, y);
              g.lineTo(900, y + 18); g.stroke();
            }
            for (let x = 0; x < 900; x += 7) {
              g.strokeStyle = x % 14 === 0 ? '#c6c4bb' : '#949187';
              g.lineWidth = 2; g.beginPath(); g.moveTo(x, 0);
              g.lineTo(x + 13, 900); g.stroke();
            }
          }
          return canvas.toDataURL('image/png').split(',')[1];
        }, pattern);
        const fixturePath = path.join(evidence, `non-text-${pattern}.png`);
        fs.writeFileSync(fixturePath, Buffer.from(png, 'base64'));
        await page.getByRole('button', {name: 'Etiket tara', exact: true}).click();
        const chooser = page.waitForEvent('filechooser');
        await page.getByRole('button', {name: 'Fotoğraf yükle / galeriden seç', exact: true}).click();
        await (await chooser).setFiles(fixturePath);
        await page.getByRole('button', {name: 'Fotoğraftaki metni oku', exact: true}).waitFor({timeout: 20000});
        const result = await page.evaluate(async () =>
          window.dokuOcr.recognizeSafe(window.__dokuSyntheticPhoto, () => {}));
        console.log(`Synthetic no-text ${pattern} OCR result:`, JSON.stringify(result));
        assert.equal(result.code, 'emptyText', `No-text ${pattern} photo cannot produce accepted label text`);
        await page.getByRole('button', {name: 'Fotoğraftaki metni oku', exact: true}).click();
        // CanvasKit does not always expose off-screen error Text in the
        // semantics tree. The visible "Tekrar oku" CTA is the failed stage.
        await page.getByRole('button', {name: 'Tekrar oku', exact: true}).waitFor({timeout: 120000});
        assert.equal(await page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true}).count(), 0);
        assert.equal(await page.getByRole('button', {name: 'Fotoğraftaki metni oku', exact: true}).count(), 0);
        console.log(`PASS ${pattern}: no fabricated OCR text offered on a no-text image.`);
      } finally { await context.close(); }
    }
    stage = 'browser safety scenarios';
    await require('./web_ocr_safety.cjs')(browser, baseUrl, evidence);
    stage = '9–12 degree edge OCR and expanded bounds';
    await require('./web_ocr_edge_regression.cjs')(browser, baseUrl, evidence);
    stage = 'real mobile crop/rotate UI and exact preview OCR';
    await require('./web_ocr_crop_smoke.cjs')(browser, baseUrl, evidence);
    stage = 'cropped no-text/year and EXIF orientation';
    await require('./web_ocr_crop_safety.cjs')(browser, baseUrl, evidence);
  } finally { await browser.close(); }
})().catch(error => {
  const message = error.stack || String(error);
  fs.writeFileSync(path.join(evidence, 'failure.json'), JSON.stringify({stage, message,
    errors: diagnosticErrors, failedRequests: diagnosticFailures,
    responses: diagnosticResponses, warnings: diagnosticWarnings}, null, 2));
  const diagnostics = JSON.stringify({errors: diagnosticErrors, failedRequests: diagnosticFailures,
    responses: diagnosticResponses, warnings: diagnosticWarnings});
  const annotation = `${stage}: ${message}\n${diagnostics}`.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
  console.error(`::error title=Web OCR verification::${annotation}`);
  console.error(error); process.exitCode = 1;
});
