'use strict';
// Chromium's fake camera provides a real MediaStream without user photos.
// This browser test never saves frames, raw OCR, EXIF or a screenshot.
const assert = require('node:assert/strict');
const {chromium} = require('../tool/web_ocr/node_modules/playwright');
const baseUrl = process.argv[2] || 'http://127.0.0.1:8082/etiket/';

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream']
  });
  try {
    const context = await browser.newContext({
      locale: 'tr-TR', viewport: {width: 390, height: 844},
      isMobile: true, hasTouch: true,
      permissions: ['camera'],
      userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36'
    });
    const page = await context.newPage();
    const unexpectedWrites = [];
    page.on('request', request => {
      if (!['GET', 'HEAD'].includes(request.method())) {
        unexpectedWrites.push({method: request.method(), url: request.url()});
      }
    });
    await page.goto(baseUrl, {waitUntil: 'networkidle'});
    await page.locator('flt-semantics-placeholder').click({force: true});
    await page.getByRole('button', {name: 'Etiket tara', exact: true}).click();
    await page.getByRole('button', {name: 'Fotoğraf çek', exact: true}).click();
    const dialog = page.getByRole('dialog', {name: 'Doku canlı kamera'});
    await dialog.waitFor({timeout: 15000});
    await page.waitForFunction(() => {
      const video = document.querySelector('[role="dialog"] video');
      return video && video.videoWidth > 0 && video.videoHeight > 0 &&
        video.srcObject?.getVideoTracks()[0]?.readyState === 'live';
    }, null, {timeout: 25000});
    const details = await page.evaluate(() => {
      const video = document.querySelector('[role="dialog"] video');
      window.__dokuTestTrack = video.srcObject.getVideoTracks()[0];
      return {width: video.videoWidth, height: video.videoHeight};
    });
    assert.ok(details.width > 0 && details.height > 0, 'fake camera delivered live frames');
    assert.equal(await dialog.getByText('Canlı OCR henüz etkin değil', {exact: false}).count() > 0, true);
    await dialog.getByRole('button', {name: 'Fotoğrafı çek', exact: true}).click();
    await dialog.waitFor({state: 'detached', timeout: 25000});
    await page.getByRole('button', {name: 'Fotoğraftaki metni oku', exact: true})
      .waitFor({timeout: 25000});
    assert.equal(await page.evaluate(() => window.__dokuTestTrack.readyState), 'ended',
      'captured photo must release the live camera');
    assert.deepEqual(unexpectedWrites, [], 'no video or photo is uploaded');
    console.log('PASS Chromium fake-camera: live rear-camera preview, local still adoption, stopped stream, no uploads.');
    await context.close();
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.stack || String(error));
  process.exitCode = 1;
});
