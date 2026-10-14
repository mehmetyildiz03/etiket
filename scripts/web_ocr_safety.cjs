'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
module.exports = async (browser, baseUrl, evidence) => {
  const context = await browser.newContext({viewport: {width: 390, height: 900}, isMobile: true, hasTouch: true,
    userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36'});
  const page = await context.newPage(), errors = [], expectedFailures = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('requestfailed', request => expectedFailures.push(request.url()));
  const button = async name => {
    const target = page.getByRole('button', {name, exact: true});
    for (let i = 0; i < 12 && await target.count() === 0; i++) {
      await page.mouse.move(195, 650); await page.mouse.wheel(0, 350); await page.waitForTimeout(100);
    }
    await target.click();
  };
  const open = async () => {
    await page.goto(baseUrl, {waitUntil: 'networkidle'});
    await page.locator('flt-semantics-placeholder').click({force: true});
    await page.getByRole('button', {name: 'Etiket tara', exact: true}).waitFor();
    await button('Etiket tara');
    await page.getByRole('button', {name: 'Fotoğraf yükle / galeriden seç', exact: true}).waitFor();
  };
  const seen = async text => page.locator(`[aria-label*="${text}"]`).or(page.getByText(text)).first().waitFor({timeout: 30000});
  const upload = async file => {
    const chooser = page.waitForEvent('filechooser');
    await button('Fotoğraf yükle / galeriden seç');
    await (await chooser).setFiles(file);
  };
  const fixture = path.join(evidence, 'synthetic-label.png');
  try {
    await open();
    // Browser sends the real file-picker cancel event; no new photo is adopted.
    let chooser = page.waitForEvent('filechooser');
    await button('Fotoğraf yükle / galeriden seç'); await chooser;
    await page.locator('input[type=file]').evaluate(input => input.dispatchEvent(new Event('cancel')));
    await seen('Fotoğraf seçimi iptal edildi.');
    await page.evaluate(() => {
      window.originalFileClick = HTMLInputElement.prototype.click;
      HTMLInputElement.prototype.click = function() { throw new DOMException('test permission refusal', 'NotAllowedError'); };
    });
    await button('Fotoğraf çek'); await seen('Fotoğraf erişimine izin verilmedi.');
    await page.evaluate(() => { HTMLInputElement.prototype.click = window.originalFileClick; delete window.originalFileClick; });
    await upload({name: 'broken.png', mimeType: 'image/png', buffer: Buffer.from('not an image')});
    await seen('Fotoğraf okunamadı.');
    await upload(fixture);
    await context.setOffline(true);
    await button('Fotoğraftaki metni oku');
    await seen('OCR motoru veya dil modeli yüklenemedi.');
    await context.setOffline(false);
    // Fresh context has no model cache. Block the actual model requests.
    await context.route('**/ocr/lang/*.gz', route => route.abort('failed'));
    await button('Tekrar oku');
    await seen('OCR motoru veya dil modeli yüklenemedi.');
    await context.unroute('**/ocr/lang/*.gz');
    await button('Tekrar oku');
    const review = page.getByRole('button', {name: 'Metni incele ve düzelt', exact: true});
    for (let i = 0; i < 120 && await review.count() === 0; i++) {
      await page.mouse.move(195, 650); await page.mouse.wheel(0, 120); await page.waitForTimeout(500);
    }
    await review.waitFor();
    // Keep the reusable worker alive, release this photo, and process a new one offline.
    await page.evaluate(() => window.dokuOcr.cancelSelection());
    await page.evaluate(() => { window.ocrSafetyPhoto = null; });
    // This picker still opens through a user gesture. Save the returned photo so
    // bridge reuse/offline is measured with REAL OCR, separate from UI approval.
    chooser = page.waitForEvent('filechooser');
    await page.evaluate(() => { window.ocrSafetyPending = window.dokuOcr.pick(false); });
    await (await chooser).setFiles(fixture);
    await page.evaluate(async () => { window.ocrSafetyPhoto = await window.ocrSafetyPending; });
    await context.setOffline(true);
    const offlineRaw = await page.evaluate(() => window.dokuOcr.recognize(window.ocrSafetyPhoto.path, () => {}));
    assert.match(offlineRaw, /70%\s+PAMUK/i);
    await context.setOffline(false);
    await page.evaluate(() => { window.dokuOcr.release(window.ocrSafetyPhoto.path); delete window.ocrSafetyPhoto; delete window.ocrSafetyPending; });
    // Cancel a real worker while its core download is delayed, then leave to
    // pasted text; the old OCR must not overwrite the user's correction.
    await open();
    await upload(fixture);
    await context.route('**/ocr/core/*', async route => {
      await new Promise(resolve => setTimeout(resolve, 700));
      try { await route.continue(); } catch (_) { /* canceled worker request */ }
    });
    await button('Fotoğraftaki metni oku');
    await button('İşlemi iptal et');
    await button('Metin yapıştır');
    const field = page.getByRole('textbox', {name: /Etiket metni/});
    await field.fill('80% CO 20% PES');
    await page.waitForTimeout(1500);
    assert.equal(await field.inputValue(), '80% CO 20% PES');
    await context.unroute('**/ocr/core/*');
    assert.deepEqual(errors, []);
    assert.ok(expectedFailures.length >= 1);
    assert.ok(expectedFailures.every(url => url.includes('/ocr/lang/') || url.includes('/ocr/core/') || url.endsWith('/ocr/worker.min.js')));
    const report = {pickerCancel: true, permissionRefusal: true, corruptPhoto: true,
      firstUseOfflineFailure: true, modelLoadFailureAndRetry: true, warmWorkerOfflineOcr: offlineRaw,
      canceledWorkerCannotOverwriteManualText: true, expectedFailures, uncaughtErrors: errors};
    fs.writeFileSync(path.join(evidence, 'safety-report.json'), JSON.stringify(report, null, 2));
    console.log('PASS browser safety: canceled picker, permission refusal, corrupt image, first-use offline failure, real model failure/retry, warm-worker offline OCR, canceled worker preserves manual text.');
  } finally { await context.close(); }
};
