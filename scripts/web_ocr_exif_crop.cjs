'use strict';
const assert = require('node:assert/strict');
const {chromium, webkit} = require('../tool/web_ocr/node_modules/playwright');

// A standards-compliant synthetic JPEG is drawn by each browser's canvas.
// Insert a minimal EXIF orientation APP1 segment after the JPEG SOI marker.
// The red/blue halves are generated, never taken from a user photo.
function jpegWithOrientation(jpeg, orientation) {
  assert.equal(jpeg.readUInt16BE(0), 0xffd8);
  const exif = Buffer.from(
    'ffe100224578696600004d4d002a00000008000101120003000000010006000000000000', 'hex');
  exif[29] = orientation; // Big-endian TIFF tag 0x0112, SHORT value.
  return Buffer.concat([jpeg.subarray(0, 2), exif, jpeg.subarray(2)]);
}

async function run(engine, baseUrl) {
  const browser = await engine.launch({headless:true});
  try {
    const context = await browser.newContext({viewport:{width:390,height:844},locale:'tr-TR'});
    try {
      const page = await context.newPage();
      await page.goto(baseUrl, {waitUntil:'networkidle'});
      assert.equal(await page.evaluate(() => window.dokuOcr?.supported), true);
      const jpeg = Buffer.from(await page.evaluate(() => {
        const canvas = document.createElement('canvas');
        canvas.width = 160; canvas.height = 100;
        const c = canvas.getContext('2d');
        c.fillStyle = '#ff0000'; c.fillRect(0, 0, 80, 100);
        c.fillStyle = '#0000ff'; c.fillRect(80, 0, 80, 100);
        return canvas.toDataURL('image/jpeg', .98).split(',')[1];
      }), 'base64');
      for (const orientation of [6, 8]) {
        const chooserPromise = page.waitForEvent('filechooser');
        await page.evaluate(() => { window.__exifPick = window.dokuOcr.pick(false); });
        const chooser = await chooserPromise;
        await chooser.setFiles({
          name: 'synthetic-exif.jpg', mimeType:'image/jpeg',
          buffer: jpegWithOrientation(jpeg, orientation)
        });
        const source = await page.evaluate(async () => {
          window.__exifSource = await window.__exifPick;
          return {width:window.__exifSource.sourceWidth,
            height:window.__exifSource.sourceHeight};
        });
        assert.deepEqual(source, {width:100,height:160},
          engine.name() + ' EXIF ' + orientation + ': crop editor dimensions must be oriented');
        const edits = [
          {name:'top',left:0,top:0,width:1,height:.5,quarterTurns:0},
          {name:'bottom',left:0,top:.5,width:1,height:.5,quarterTurns:0},
          {name:'rotated-left',left:0,top:0,width:.5,height:1,quarterTurns:1}
        ];
        const means = {};
        for (const edit of edits) {
          const result = await page.evaluate(async options => {
            const output = await window.dokuOcr.editSafe(window.__exifSource.path, options);
            if (output.code || !output.photo) return {error:output.code};
            const photo = output.photo;
            const fetched = new Uint8Array(await (await fetch(photo.path)).arrayBuffer());
            const identical = fetched.length === photo.bytes.length &&
              fetched.every((value,i) => value === photo.bytes[i]);
            window.dokuOcr.release(photo.path);
            return {identical,mean:photo.quality?.meanLuminance ?? null};
          }, edit);
          assert.equal(result.error, undefined, engine.name() + ' crop ' + edit.name);
          assert.equal(result.identical, true, 'OCR Blob must equal visible edited PNG');
          assert.ok(Number.isFinite(result.mean), 'preprocessing quality probe must sample selected pixels');
          means[edit.name] = result.mean;
        }
        // Red has greater luminance than blue. EXIF 6 rotates red to the
        // top; EXIF 8 rotates it to the bottom. Quarter-turn 1 maps the
        // displayed bottom half to the rotated left half.
        const difference = means.top - means.bottom;
        assert.ok((orientation === 6 ? difference : -difference) > 25,
          engine.name() + ' EXIF ' + orientation + ': wrong top/bottom crop ' + JSON.stringify(means));
        assert.ok(Math.abs(means['rotated-left'] - means.bottom) < 10,
          engine.name() + ' EXIF ' + orientation + ': quarter-turn crop mismatch ' + JSON.stringify(means));
        await page.evaluate(() => {
          window.dokuOcr.release(window.__exifSource.path);
          delete window.__exifSource;
          delete window.__exifPick;
        });
        console.log('PASS ' + engine.name() + ' synthetic EXIF ' + orientation +
          ' -> oriented crop, quarter-turn, OCR-bound PNG; means ' + JSON.stringify(means));
      }
    } finally { await context.close(); }
  } finally { await browser.close(); }
}

(async () => {
  const baseUrl = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
  await run(chromium, baseUrl);
  await run(webkit, baseUrl);
})().catch(error => { console.error('::error title=EXIF browser crop::', error); process.exitCode = 1; });
