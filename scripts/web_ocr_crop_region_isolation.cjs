'use strict';
// D4.2: REAL Chromium/Tesseract WASM on two separate SYNTHETIC crop regions.
// A crop must send only its own source pixels to OCR, not the original frame
// or the previously edited region. No private images, EXIF or OCR are stored.
const assert = require('node:assert/strict');

module.exports = async (browser, baseUrl) => {
  const context = await browser.newContext({
    locale: 'tr-TR', viewport: {width: 390, height: 844}
  });
  const page = await context.newPage();
  const methods = [];
  page.on('request', request => methods.push(request.method()));
  try {
    await page.goto(baseUrl, {waitUntil: 'networkidle'});
    const fixture = await page.evaluate(() => {
      const canvas = document.createElement('canvas');
      canvas.width = 1600; canvas.height = 800;
      const g = canvas.getContext('2d');
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, canvas.width, canvas.height);
      g.fillStyle = '#000000';
      g.font = 'bold 58px Arial';
      // Two independent compositions. The other region is deliberately
      // contradictory, so using the full image cannot pass both crop checks.
      g.fillText('80% PAMUK', 90, 280);
      g.fillText('20% POLYESTER', 90, 430);
      g.fillText('60% COTTON', 920, 280);
      g.fillText('40% WOOL', 920, 430);
      return canvas.toDataURL('image/png').split(',')[1];
    });
    const chooser = page.waitForEvent('filechooser');
    await page.evaluate(() => { window.__splitPick = dokuOcr.pick(false); });
    await (await chooser).setFiles({
      name: 'synthetic-split-label.png', mimeType: 'image/png',
      buffer: Buffer.from(fixture, 'base64')
    });
    const selected = await page.evaluate(async () => {
      window.__splitSource = await window.__splitPick;
      return {width: __splitSource.sourceWidth, height: __splitSource.sourceHeight};
    });
    assert.deepEqual(selected, {width: 1600, height: 800});
    const regions = [
      {name: 'left', left: .05, top: .12, width: .42, height: .76,
        own: [/80\s*%\s*PAMUK/i, /20\s*%\s*POLYESTER/i],
        other: [/60\s*%\s*COTTON/i, /40\s*%\s*WOOL/i]},
      {name: 'right', left: .53, top: .12, width: .42, height: .76,
        own: [/60\s*%\s*COTTON/i, /40\s*%\s*WOOL/i],
        other: [/80\s*%\s*PAMUK/i, /20\s*%\s*POLYESTER/i]}
    ];
    for (const region of regions) {
      const result = await page.evaluate(async crop => {
        const edited = await dokuOcr.editSafe(window.__splitSource.path, {
          left: crop.left, top: crop.top, width: crop.width,
          height: crop.height, quarterTurns: 0
        });
        if (edited.code || !edited.photo) return {editError: edited.code};
        try {
          // Decode exactly the edited Blob URL passed to recognizeSafe.
          const image = new Image();
          image.src = edited.photo.path;
          await image.decode();
          const dimensions = {width: image.naturalWidth, height: image.naturalHeight};
          const recognized = await dokuOcr.recognizeSafe(edited.photo.path, () => {});
          return {dimensions, code: recognized.code, text: recognized.text,
            decision: recognized.observation?.decision,
            acceptedText: recognized.observation?.acceptedText};
        } finally {
          dokuOcr.release(edited.photo.path);
        }
      }, region);
      assert.equal(result.editError, undefined, region.name + ' crop must succeed');
      assert.ok(result.dimensions.width < 1600 && result.dimensions.height > 0,
        region.name + ' must be a real cropped image, not the full 1600px source');
      assert.equal(result.code, null, region.name + ' should be reviewable');
      assert.equal(result.decision, 'candidate');
      assert.equal(result.acceptedText, result.text);
      for (const pattern of region.own)
        assert.match(result.text, pattern, region.name + ' must preserve its printed percentage/fiber');
      for (const pattern of region.other)
        assert.doesNotMatch(result.text, pattern, region.name + ' must exclude the other composition');
      console.log('PASS synthetic split crop ' + region.name +
        ': both printed percentage/fiber pairs, no cross-region OCR contamination');
    }
    assert.ok(methods.every(method => method === 'GET' || method === 'HEAD'),
      'No photo or OCR text upload');
    await page.evaluate(() => {
      dokuOcr.release(window.__splitSource.path);
      window.__splitSource = window.__splitPick = null;
    });
  } finally {
    await context.close();
  }
};
