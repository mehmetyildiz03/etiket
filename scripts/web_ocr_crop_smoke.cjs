'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
module.exports = async (browser, baseUrl, evidence) => {
  const report = [];
  for (const [width, turns, kind] of [
    [360, 0, 'portrait'],
    [390, 3, 'textured-small'],
    [430, 2, 'dark'],
    [1280, 1, 'landscape'],
  ]) {
    const context = await browser.newContext({
      locale: 'tr-TR',
      viewport: { width, height: width === 360 ? 800 : 844 },
      isMobile: width < 500,
      hasTouch: width < 500,
    });
    const page = await context.newPage(),
      errors = [],
      failures = [],
      requests = [],
      assets = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('requestfailed', (r) => failures.push(r.url()));
    page.on('console', (m) => {
      if (m.type() === 'error') errors.push(m.text());
    });
    page.on('request', (r) => requests.push({ url: r.url(), method: r.method() }));
    page.on('response', (r) => {
      if (r.url().includes('/ocr/')) assets.push({ url: r.url(), status: r.status() });
    });
    await page.route('**/doku_ocr.js', async (route) => {
      const response = await route.fetch();
      const body = (await response.text())
        .replace(
          'globalThis.dokuOcr = Object.freeze',
          'globalThis.__cropResources = () => ({photos: photos.size, canvasPixels, canvases: canvases.size}); globalThis.dokuOcr = Object.freeze',
        )
        .replace(
          'photos.set(path, {blob, source});',
          'photos.set(path, {blob, source}); globalThis.__cropPhoto = {url:path, blob, sourceBytes:source.preview};',
        );
      await route.fulfill({ response, body });
    });
    const frame = () =>
      page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const target = async (role, name) => {
      const item = page.getByRole(role, { name, exact: true });
      for (let n = 0; n < 30 && (await item.count()) === 0; n++) {
        await page.mouse.move(width / 2, 500);
        await page.mouse.wheel(0, n < 15 ? 260 : -260);
        await page.waitForTimeout(80);
      }
      await item.waitFor();
      return item;
    };
    const button = async (name) => {
      await (await target('button', name)).click();
      await frame();
    };
    // Activate the real editing client through keyboard focus. Flutter’s
    // virtual scroll semantics can reflow while a pointer click is targeting it.
    const input = async (name, value) => {
      const field = await target('textbox', name);
      await field.focus();
      await frame();
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.insertText(value);
      await page.keyboard.press('Tab');
      await frame();
    };
    try {
      await page.goto(baseUrl, { waitUntil: 'networkidle' });
      const semantics = page.locator('flt-semantics-placeholder');
      // Browser UA is desktop here, with mobile viewport/touch enabled.
      await semantics.evaluate((e) => e.click());
      await page.getByRole('button', { name: 'Etiket tara', exact: true }).waitFor();
      await page.evaluate(() => {
        window.__hash = async (blob) =>
          Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())))
            .map((n) => n.toString(16).padStart(2, '0'))
            .join('');
        const createWorker = Tesseract.createWorker;
        Tesseract.createWorker = async (...args) => {
          const worker = await createWorker(...args),
            recognize = worker.recognize.bind(worker);
          worker.recognize = async (blob, ...rest) => {
            window.__recognizedHash = await window.__hash(blob);
            return recognize(blob, ...rest);
          };
          return worker;
        };
      });
      const fixture = await page.evaluate(
        ({ turns, kind }) => {
          const w = kind === 'portrait' ? 1280 : 2400,
            h = kind === 'portrait' ? 1800 : 1600;
          const label = {
            x: Math.round(w * 0.22),
            y: Math.round(h * 0.19),
            w: kind === 'portrait' ? 650 : 720,
            h: 360,
          };
          const c = document.createElement('canvas');
          c.width = w;
          c.height = h;
          const g = c.getContext('2d');
          const dark = kind === 'dark';
          g.fillStyle = dark ? '#292c2b' : '#94988d';
          g.fillRect(0, 0, w, h);
          for (let y = 0; y < h; y += 6) {
            g.strokeStyle = dark ? '#42463d' : '#5d675b';
            g.beginPath();
            g.moveTo(0, y);
            g.lineTo(w, y + 20);
            g.stroke();
          }
          for (let x = 0; x < w; x += 7) {
            g.strokeStyle = dark ? '#20241e' : '#bcc3ac';
            g.beginPath();
            g.moveTo(x, 0);
            g.lineTo(x + 17, h);
            g.stroke();
          }
          // This distinct violet strip sits LEFT of the label and lets us
          // assert from browser SCREENSHOT PIXELS that the ORIGINAL source
          // really renders in Flutter, not merely that a widget exists.
          g.fillStyle = '#a12be2';
          g.fillRect(Math.round(w * .02), Math.round(h * .08),
            Math.round(w * .17), Math.round(h * .76));
          g.fillStyle = dark ? '#a7a494' : '#f2efe5';
          g.fillRect(label.x, label.y, label.w, label.h);
          g.fillStyle = '#151c17';
          g.font = 'bold 38px Arial';
          ['SHELL', '80% PAMUK', '20% POLYESTER'].forEach((text, i) =>
            g.fillText(text, label.x + 30, label.y + 75 + i * 100),
          );
          const rotated = document.createElement('canvas'),
            sourceTurns = (4 - turns) % 4;
          rotated.width = sourceTurns % 2 ? h : w;
          rotated.height = sourceTurns % 2 ? w : h;
          const r = rotated.getContext('2d');
          if (sourceTurns === 1) {
            r.translate(h, 0);
            r.rotate(Math.PI / 2);
          } else if (sourceTurns === 2) {
            r.translate(w, h);
            r.rotate(Math.PI);
          } else if (sourceTurns === 3) {
            r.translate(0, w);
            r.rotate(-Math.PI / 2);
          }
          r.drawImage(c, 0, 0);
          return {
            png: rotated.toDataURL('image/png').split(',')[1],
            crop: { left: label.x / w, top: label.y / h, width: label.w / w, height: label.h / h },
          };
        },
        { turns, kind },
      );
      const file = path.join(evidence, `crop-${width}-${kind}-source.png`);
      fs.writeFileSync(file, Buffer.from(fixture.png, 'base64'));
      await button('Etiket tara');
      const chooser = page.waitForEvent('filechooser');
      await button('Fotoğraf yükle / galeriden seç');
      await (await chooser).setFiles(file);
      await target('button', 'Fotoğrafı düzenle');
      const full = await page.evaluate(() => window.dokuOcr.recognizeSafe(window.__cropPhoto.url, () => {}));
      // Record the original full-frame outcome without inventing a success rate.
      await button('Fotoğrafı düzenle');
      await page
        .getByText('Orijinal fotoğraf', { exact: true })
        .or(page.locator('[aria-label*="Orijinal fotoğraf"]'))
        .first()
        .waitFor();
      const handle = page.getByText('Sağ alt köşe', { exact: true }).locator('..');
      await handle.waitFor();
      await page.waitForTimeout(350); // Wait for the real DialogRoute transition before measuring touch coordinates.
      // Test the actual painted pixels. Earlier tests only found crop widgets;
      // an iPhone user reported a blank original image behind those widgets.
      let violet = 0;
      for (let attempt = 0; attempt < 8; attempt++) {
        const screenshot = await page.screenshot();
        violet = await page.evaluate(async encoded => {
          const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0));
          const bitmap = await createImageBitmap(new Blob([bytes], {type: 'image/png'}));
          const canvas = document.createElement('canvas');
          canvas.width = bitmap.width; canvas.height = bitmap.height;
          const context = canvas.getContext('2d', {willReadFrequently: true});
          context.drawImage(bitmap, 0, 0);
          bitmap.close();
          const data = context.getImageData(0, 0, canvas.width, canvas.height).data;
          let count = 0;
          for (let i = 0; i < data.length; i += 4) {
            if (data[i] > 130 && data[i] < 200 &&
                data[i + 1] < 85 && data[i + 2] > 175) count++;
          }
          return count;
        }, screenshot.toString('base64'));
        if (violet >= 100) break;
        await page.waitForTimeout(200);
      }
      assert.ok(violet >= 100, 'Original camera photo MUST be painted in the crop dialog: '+violet+' violet pixels');
      const previewSignature = await page.evaluate(() => {
        const bytes = window.__cropPhoto?.sourceBytes;
        return bytes == null ? null : [...bytes.slice(0, 8)];
      });
      assert.deepEqual(previewSignature, [137,80,78,71,13,10,26,10], 'Web crop source thumbnail uses lossless PNG');

      const box = await handle.boundingBox();
      assert.ok(box.width >= 43.99 && box.height >= 43.99, JSON.stringify(box));
      if (width < 500) {
        const cdp = await context.newCDPSession(page);
        await cdp.send('Input.dispatchTouchEvent', {
          type: 'touchStart',
          touchPoints: [{ x: box.x + 22, y: box.y + 22 }],
        });
        await frame();
        for (let n = 1; n <= 8; n++) {
          await cdp.send('Input.dispatchTouchEvent', {
            type: 'touchMove',
            touchPoints: [{ x: box.x + 22 - n * 7, y: box.y + 22 - n * 5 }],
          });
          await frame();
        }
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        await cdp.detach();
      } else {
        await page.mouse.move(box.x + 22, box.y + 22);
        await page.mouse.down();
        await page.mouse.move(box.x - 5, box.y + 2, { steps: 4 });
        await page.mouse.up();
      }
      await frame();
      const dragged = {};
      for (const name of ['Genişlik (%)', 'Yükseklik (%)']) {
        const field = await target('textbox', name);
        await field.focus();
        await frame();
        for (let n = 0; n < 40 && !(await field.inputValue()); n++) await page.waitForTimeout(25);
        dragged[name] = Number(await field.inputValue());
        assert.ok(
          dragged[name] > 0 && dragged[name] < 100,
          `${name}: real drag changes the selection: ${dragged[name]}`,
        );
        await page.keyboard.press('Tab');
      }
      await button('Sıfırla');
      for (let n = 0; n < turns; n++) await button('90° sağa');
      for (const [name, key] of [
        ['Sol (%)', 'left'],
        ['Üst (%)', 'top'],
        ['Genişlik (%)', 'width'],
        ['Yükseklik (%)', 'height'],
      ])
        await input(name, (fixture.crop[key] * 100).toFixed(4));
      await page.screenshot({ path: path.join(evidence, `crop-${width}-editor.png`) });
      await button('Kırpmayı uygula');
      await target('button', 'Tekrar düzenle');
      const preview = await page.evaluate(async () => {
        const blob = window.__cropPhoto.blob,
          bitmap = await createImageBitmap(blob);
        const result = {
          hash: await window.__hash(blob),
          width: bitmap.width,
          height: bitmap.height,
          png: Array.from(new Uint8Array(await blob.arrayBuffer())),
        };
        bitmap.close();
        return result;
      });
      assert.ok(preview.width <= 2400 && preview.height <= 2400 && preview.width * preview.height <= 6000000);
      fs.writeFileSync(path.join(evidence, `crop-${width}-processed.png`), Buffer.from(preview.png));
      delete preview.png;
      await button('Fotoğraftaki metni oku');
      const review = page.getByRole('button', { name: 'Metni incele ve düzelt', exact: true });
      for (let i = 0; i < 240 && (await review.count()) === 0; i++) {
        await page.mouse.move(width / 2, 500);
        await page.mouse.wheel(0, i % 20 < 10 ? 100 : -100);
        await page.waitForTimeout(250);
      }
      await review.click();
      await frame();
      const field = page.getByRole('textbox', { name: /Etiket metni/ });
      await field.focus();
      await frame();
      const raw = await field.inputValue();
      assert.match(raw, /80\s*%\s*PAMUK/i);
      assert.match(raw, /20\s*%\s*POLYESTER/i);
      assert.equal(
        await page.evaluate(() => window.__recognizedHash),
        preview.hash,
        'OCR receives the exact approved preview',
      );
      await field.fill('80% CO 20% PES');
      await page.keyboard.press('Tab');
      await frame();
      // Return to the same retained original, cancel another edit, then re-read.
      await button('Geri');
      await button('Tekrar düzenle');
      await button('90° sola');
      await button('Düzenlemeyi iptal et');
      const current = await page.evaluate(() => window.__hash(window.__cropPhoto.blob));
      assert.equal(current, preview.hash, 'Cancel keeps the committed photo');
      await button('Yeniden oku');
      await review.waitFor({ timeout: 120000 });
      await review.click();
      await frame();
      await page.getByText('Önceki metin değiştirilsin mi?', { exact: true }).waitFor();
      await button('Metnimi koru');
      await button('Metin yapıştır');
      const corrected = page.getByRole('textbox', { name: /Etiket metni/ });
      await corrected.focus();
      await frame();
      for (let n = 0; n < 40 && (await corrected.inputValue()) !== '80% CO 20% PES'; n++)
        await page.waitForTimeout(50);
      assert.equal(await corrected.inputValue(), '80% CO 20% PES', 'User correction survived crop/re-read');
      await button('Metni ayrıştır');
      await button('Düzenleyicide incele');
      assert.equal(await page.getByRole('button', { name: 'Devam et', exact: true }).isEnabled(), false);
      const confirm = await target('checkbox', 'Etiketle karşılaştırdım ve doğruladım');
      if (width < 500) await confirm.tap();
      else await confirm.click();
      await page.locator('[role=checkbox][aria-checked=true]').waitFor();
      assert.equal(await page.getByRole('button', { name: 'Devam et', exact: true }).isEnabled(), true);
      assert.deepEqual(await page.evaluate(() => window.__cropResources()), {
        photos: 0,
        canvasPixels: 0,
        canvases: 0,
      });
      assert.ok(requests.every((r) => ['GET', 'HEAD'].includes(r.method)));
      assert.deepEqual(errors, []);
      assert.deepEqual(failures, []);
      for (const part of ['worker.min.js', '/core/', '/lang/tur.traineddata.gz', '/lang/eng.traineddata.gz'])
        assert.ok(assets.some((a) => a.url.includes(part) && a.status === 200));
      report.push({
        width,
        kind,
        turns,
        full,
        croppedRaw: raw,
        preview,
        exactPreviewInput: true,
        dragged,
        touchTarget: box,
        localResourcesReleased: true,
        cropSourceVisibleVioletPixels: violet,
        sourcePreviewFormat: 'png',
        errors,
        failures,
      });
      fs.writeFileSync(path.join(evidence, 'crop-report.json'), JSON.stringify(report, null, 2));
      console.log(
        `PASS ${width} crop UI: ${kind}, ${turns * 90}deg, real 80%/20%, exact preview hash, corrections/approval, resource cleanup.`,
      );
    } catch (error) {
      await page.screenshot({ path: path.join(evidence, `crop-failure-${width}.png`) }).catch(() => {});
      fs.writeFileSync(path.join(evidence, `crop-failure-${width}.html`), await page.content());
      throw error;
    } finally {
      await context.close();
    }
  }
};
if (require.main === module)
  (async () => {
    const { chromium } = require('../tool/web_ocr/node_modules/playwright');
    const evidence = path.resolve(process.env.OCR_EVIDENCE_DIR || 'build/web-ocr-crop-evidence');
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
    console.error(`::error title=Crop OCR verification::${String(error).replace(/\n/g, '%0A')}`);
    console.error(error);
    process.exitCode = 1;
  });
