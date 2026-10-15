'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

module.exports = async (browser, baseUrl, evidence) => {
  const context = await browser.newContext({ locale: 'tr-TR', viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  const requests = [],
    errors = [],
    report = [];
  page.on('request', (r) => requests.push({ url: r.url(), method: r.method() }));
  page.on('pageerror', (e) => errors.push(e.message));
  await page.route('**/doku_ocr.js', async (route) => {
    const response = await route.fetch();
    const body = (await response.text()).replace(
      'globalThis.dokuOcr = Object.freeze',
      'globalThis.__cropResources = () => ({photos:photos.size, canvasPixels, canvases:canvases.size}); globalThis.dokuOcr = Object.freeze',
    );
    await route.fulfill({ response, body });
  });
  try {
    await page.goto(baseUrl, { waitUntil: 'networkidle' });
    for (const pattern of [
      'blank',
      'woven',
      'year',
      'no-ratios',
      'exif-3',
      'exif-6',
      'exif-8',
      'exif-mirror',
    ]) {
      const data = await page.evaluate(async (pattern) => {
        const c = document.createElement('canvas');
        c.width = 900;
        c.height = 600;
        const g = c.getContext('2d');
        g.fillStyle = pattern === 'woven' ? '#96998d' : '#f1eee5';
        g.fillRect(0, 0, 900, 600);
        if (pattern === 'woven') {
          for (let y = 0; y < 600; y += 5) {
            g.strokeStyle = '#5a6759';
            g.beginPath();
            g.moveTo(0, y);
            g.lineTo(900, y + 5);
            g.stroke();
          }
          for (let x = 0; x < 900; x += 7) {
            g.strokeStyle = '#c3c9b5';
            g.beginPath();
            g.moveTo(x, 0);
            g.lineTo(x + 8, 600);
            g.stroke();
          }
        } else if (pattern !== 'blank') {
          g.fillStyle = '#000';
          g.font = 'bold 48px Arial';
          const lines =
            pattern === 'year'
              ? ['2026 COTTON']
              : pattern === 'no-ratios'
                ? ['COTTON', 'POLYESTER']
                : ['80% PAMUK', '20% POLYESTER'];
          lines.forEach((line, i) => g.fillText(line, 75, 170 + i * 150));
        }
        if (!pattern.startsWith('exif'))
          return {
            bytes: Array.from(new Uint8Array(await (await new Promise((r) => c.toBlob(r))).arrayBuffer())),
            type: 'image/png',
          };
        let source = c;
        if (pattern === 'exif-mirror') {
          source = document.createElement('canvas');
          source.width = 900;
          source.height = 600;
          const m = source.getContext('2d');
          m.translate(900, 0);
          m.scale(-1, 1);
          m.drawImage(c, 0, 0);
        }
        const jpeg = new Uint8Array(
          await (await new Promise((r) => source.toBlob(r, 'image/jpeg', 0.95))).arrayBuffer(),
        );
        const orientation = pattern === 'exif-mirror' ? 2 : Number(pattern.slice(5));
        // Minimal standards-compliant EXIF/TIFF orientation in a JPEG APP1.
        const exif = new Uint8Array([
          255,
          225,
          0,
          34,
          69,
          120,
          105,
          102,
          0,
          0,
          73,
          73,
          42,
          0,
          8,
          0,
          0,
          0,
          1,
          0,
          18,
          1,
          3,
          0,
          1,
          0,
          0,
          0,
          orientation,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
        const out = new Uint8Array(jpeg.length + exif.length);
        out.set(jpeg.subarray(0, 2));
        out.set(exif, 2);
        out.set(jpeg.subarray(2), 2 + exif.length);
        return { bytes: Array.from(out), type: 'image/jpeg' };
      }, pattern);
      fs.writeFileSync(
        path.join(evidence, `${pattern}-source.${data.type.endsWith('jpeg') ? 'jpg' : 'png'}`),
        Buffer.from(data.bytes),
      );
      const chooser = page.waitForEvent('filechooser');
      await page.evaluate(() => {
        window.__pick = dokuOcr.pick(false);
      });
      await (await chooser).setFiles({ name: 'label', mimeType: data.type, buffer: Buffer.from(data.bytes) });
      const source = await page.evaluate(async () => {
        window.__source = await window.__pick;
        return { width: __source.sourceWidth, height: __source.sourceHeight };
      });
      const quarterTurns = pattern === 'exif-6' ? 3 : pattern === 'exif-8' ? 1 : pattern === 'exif-3' ? 2 : 0;
      const crop = await page.evaluate(async (quarterTurns) => {
        const result = await dokuOcr.editSafe(__source.path, {
          left: 0.03,
          top: 0.03,
          width: 0.94,
          height: 0.94,
          quarterTurns,
        });
        if (result.photo) window.__crop = result.photo;
        return { code: result.code };
      }, quarterTurns);
      assert.equal(crop.code, null, `${pattern} crop succeeds`);
      if (pattern === 'exif-6' || pattern === 'exif-8') assert.deepEqual(source, { width: 600, height: 900 });
      else assert.deepEqual(source, { width: 900, height: 600 });
      const output = await page.evaluate(() => dokuOcr.recognizeSafe(__crop.path, () => {}));
      if (pattern.startsWith('exif')) {
        assert.equal(output.code, null);
        assert.match(output.text, /80\s*%\s*PAMUK/i);
        assert.match(output.text, /20\s*%\s*POLYESTER/i);
      } else {
        assert.equal(output.code, 'emptyText', `${pattern} must not become a fabric proposal`);
        assert.equal(output.text, null);
      }
      await page.evaluate(() => {
        dokuOcr.release(__source.path);
        dokuOcr.release(__crop.path);
        window.__source = window.__crop = window.__pick = null;
      });
      assert.deepEqual(await page.evaluate(() => __cropResources()), {
        photos: 0,
        canvasPixels: 0,
        canvases: 0,
      });
      report.push({ pattern, source, quarterTurns, output });
      fs.writeFileSync(path.join(evidence, 'crop-safety-report.json'), JSON.stringify(report, null, 2));
      console.log(
        `PASS real cropped ${pattern}: ${output.code || output.text.trim().replace(/\n/g, ' / ')}, original orientation and resource cleanup.`,
      );
    }
    assert.ok(
      requests.every((r) => ['GET', 'HEAD'].includes(r.method)),
      'No photo/text upload',
    );
    assert.deepEqual(errors, []);
  } finally {
    await context.close();
  }
};
