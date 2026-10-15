'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { textDistance } = require('./ocr_benchmark_metrics.cjs');
module.exports = async (browser, baseUrl, evidence) => {
  const report = [];
  for (const [width, kind] of [
    [360, 'control-en'],
    [390, 'control-tr'],
    [430, 'label'],
    [390, 'label-weak'],
    [390, 'blank'],
    [390, 'woven'],
  ]) {
    const context = await browser.newContext({
      locale: 'tr-TR',
      viewport: { width, height: 844 },
      isMobile: width < 500,
      hasTouch: true,
    });
    const page = await context.newPage(),
      requests = [],
      errors = [],
      assets = [];
    page.on('request', (r) => requests.push({ url: r.url(), method: r.method() }));
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => {
      if (m.type() === 'error') errors.push(m.text());
    });
    page.on('response', (r) => {
      if (r.url().includes('/ocr/')) assets.push({ url: r.url(), status: r.status() });
    });
    const frame = () =>
      page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    const target = async (role, name) => {
      const item = page.getByRole(role, { name, exact: true });
      for (let n = 0; n < 30 && (await item.count()) === 0; n++) {
        await page.mouse.move(width / 2, 600);
        await page.mouse.wheel(0, n < 15 ? 250 : -250);
        await page.waitForTimeout(80);
      }
      await item.waitFor({ timeout: 120000 });
      return item;
    };
    const visibleText = (text) =>
      page
        .getByText(text, { exact: true })
        .or(page.locator('[aria-label*=' + JSON.stringify(text) + ']'))
        .first();
    const button = async (name) => {
      await (await target('button', name)).click();
      await frame();
    };
    try {
      await page.goto(baseUrl, { waitUntil: 'networkidle' });
      await page.locator('flt-semantics-placeholder').evaluate((e) => e.click());
      await page.getByRole('button', { name: 'Etiket tara', exact: true }).waitFor();
      await page.evaluate((forceWeak) => {
        const original = Tesseract.createWorker;
        Tesseract.createWorker = async (...args) => {
          const worker = await original(...args),
            recognize = worker.recognize.bind(worker);
          let calls = 0;
          worker.recognize = async (...args) => {
            const result = await recognize(...args);
            calls++;
            // The OCR engine runs for real. Only the FIRST confidence score
            // is forced to 48 to exercise Doku's weak-candidate second pass.
            // This synthetic scenario is a regression test, not a benchmark.
            if (forceWeak && calls === 1) result.data.confidence = 48;
            const evidence = {rawText: result.data.text, confidence: result.data.confidence};
            if (calls === 1) window.__actualWorker = evidence;
            else window.__secondaryWorker = evidence;
            return result;
          };
          return worker;
        };
      }, kind === 'label-weak');
      const fixture = await page.evaluate((kind) => {
        const c = document.createElement('canvas');
        c.width = 1200;
        c.height = 800;
        const g = c.getContext('2d');
        g.fillStyle = kind === 'woven' ? '#b2b0a5' : '#fff';
        g.fillRect(0, 0, 1200, 800);
        if (kind === 'woven') {
          for (let y = 0; y < 800; y += 5) {
            g.strokeStyle = '#75796c';
            g.beginPath();
            g.moveTo(0, y);
            g.lineTo(1200, y + 12);
            g.stroke();
          }
          for (let x = 0; x < 1200; x += 7) {
            g.strokeStyle = '#d4d3c9';
            g.beginPath();
            g.moveTo(x, 0);
            g.lineTo(x + 20, 800);
            g.stroke();
          }
        }
        const lines =
          kind === 'control-en'
            ? ['PLEASE CLOSE THE DOOR']
            : kind === 'control-tr'
              ? ['BUGÜN HAVA GÜZEL']
              : ['label', 'label-weak'].includes(kind)
                ? ['80% PAMUK', '20% POLYESTER']
                : [];
        g.fillStyle = '#000';
        g.font = 'bold 58px Arial';
        lines.forEach((t, i) => g.fillText(t, 60, 220 + i * 150));
        return { png: c.toDataURL('image/png').split(',')[1], groundTruth: lines.join('\n') };
      }, kind);
      const file = path.join(evidence, `diagnostic-${width}-${kind}.png`);
      fs.writeFileSync(file, Buffer.from(fixture.png, 'base64'));
      await button('Etiket tara');
      const chooser = page.waitForEvent('filechooser');
      await button('Fotoğraf yükle / galeriden seç');
      await (await chooser).setFiles(file);
      await target('button', 'Fotoğraftaki metni oku');
      // Observe the real production bridge called by Flutter, without changing it.
      await page.evaluate(() => {
        const original = dokuOcr;
        window.dokuOcr = {
          ...original,
          recognizeSafe: async (...args) => {
            const result = await original.recognizeSafe(...args);
            window.__diagnosticOutput = result;
            return result;
          },
        };
      });
      await button('Fotoğraftaki metni oku');
      await page.waitForFunction(() => window.__diagnosticOutput !== undefined, {}, { timeout: 120000 });
      const output = await page.evaluate(() => __diagnosticOutput),
        actual = await page.evaluate(() => __actualWorker);
      const row = {
        commit: process.env.OCR_COMMIT_SHA || process.env.GITHUB_SHA || null,
        width,
        kind,
        groundTruth: fixture.groundTruth,
        output,
        actualWorker: actual,
        rawDistance: fixture.groundTruth ? textDistance(fixture.groundTruth, actual.rawText) : null,
      };
      report.push(row);
      fs.writeFileSync(path.join(evidence, 'diagnostics-report.json'), JSON.stringify(report, null, 2));
      assert.ok(
        output.observation,
        'Production must retain raw worker evidence separately from legacy emptyText',
      );
      assert.equal(output.observation.rawText, actual.rawText);
      assert.equal(output.observation.confidence, actual.confidence);
      if (kind === 'label-weak') {
        assert.equal(actual.confidence, 48);
        const alternate = await page.evaluate(() => window.__secondaryWorker);
        assert.ok(alternate, 'real second WASM/Tesseract recognition must run');
        assert.equal(output.text, actual.rawText, 'the original OCR output must never be replaced');
        if (alternate.rawText.trim() && alternate.rawText !== actual.rawText) {
          assert.equal(output.observation.secondReading.rawText, alternate.rawText);
          assert.equal(output.observation.secondReading.confidence, alternate.confidence);
        } else {
          assert.equal(output.observation.secondReading, null);
        }
      }
      const candidate = kind === 'label' || kind === 'label-weak';
      if (candidate) assert.equal(output.observation.decision, 'candidate');
      if (kind.startsWith('control')) assert.equal(output.observation.decision, 'noComposition');
      if (kind.startsWith('control')) {
        assert.ok(actual.confidence >= 45);
        assert.match(actual.rawText, kind === 'control-en' ? /PLEASE CLOSE THE DOOR/ : /HAVA/);
        await page
          .getByText('Yazı algılandı, ancak kumaş bileşimi tespit edilemedi.', { exact: false })
          .waitFor();
        assert.equal(output.text, null);
      } else if (!candidate) {
        assert.ok(['noText', 'lowConfidence', 'noComposition'].includes(output.observation.decision));
        assert.equal(output.text, null);
      } else {
        assert.match(output.text, /80%\s+PAMUK/);
        assert.match(output.text, /20%\s+POLYESTER/);
      }
      if (!candidate && actual.rawText.trim())
        assert.equal(await visibleText(actual.rawText.trim()).count(), 0, 'Raw evidence stays opt-in');
      await button("OCR'nin okuduğu ham metni göster");
      await visibleText('Ham OCR çıktısı — doğrulanmış kumaş bileşimi değildir').waitFor();
      if (kind === 'label-weak' && output.observation.secondReading) {
        await visibleText('İkinci OCR denemesi — alternatif okuma, doğrulanmamış').waitFor();
      }
      await visibleText(
        'Etiket kararı: ' +
          (candidate
            ? 'Etiket adayı — kullanıcı doğrulaması bekliyor'
            : output.observation.decision === 'noComposition'
              ? 'Kumaş bileşimi bulunamadı — etiket adayı kabul edilmedi'
              : output.observation.decision === 'noText'
                ? 'Okunabilir metin çıkarılamadı'
                : 'Güven yetersiz — etiket adayı kabul edilmedi'),
      ).waitFor();
      await page.screenshot({ path: path.join(evidence, `diagnostic-${width}-${kind}-details.png`) });
      // Showing evidence never creates/imports a composition or edits existing text.
      if (!candidate)
        assert.equal(
          await page.getByRole('button', { name: 'Metni incele ve düzelt', exact: true }).count(),
          0,
        );
      await button('Ham OCR metnini gizle');
      assert.equal(await visibleText('Ham OCR çıktısı — doğrulanmış kumaş bileşimi değildir').count(), 0);
      if (candidate) {
        await button('Metni incele ve düzelt');
        const field = page.getByRole('textbox', { name: /Etiket metni/ });
        await field.focus();
        await frame();
        await field.fill('80% CO 20% PES');
        await button('Metni ayrıştır');
        await button('Düzenleyicide incele');
        assert.equal(await page.getByRole('button', { name: 'Devam et', exact: true }).isEnabled(), false);
      } else {
        await button('Metin yapıştır');
        const field = page.getByRole('textbox', { name: /Etiket metni/ });
        await field.focus();
        await frame();
        assert.equal(await field.inputValue(), '');
      }
      assert.ok(
        requests.every((r) => ['GET', 'HEAD'].includes(r.method)),
        'No photo/text upload',
      );
      assert.deepEqual(errors, []);
      for (const part of ['worker.min.js', '/core/', '/lang/tur.traineddata.gz', '/lang/eng.traineddata.gz'])
        assert.ok(assets.some((a) => a.url.includes(part) && a.status === 200));
      console.log(
        `PASS diagnostics ${width} ${kind}: ${output.observation.decision}, confidence=${actual.confidence}, raw distinct, opt-in, no auto import.`,
      );
    } catch (error) {
      await page
        .screenshot({ path: path.join(evidence, `diagnostic-failure-${width}-${kind}.png`) })
        .catch(() => {});
      throw error;
    } finally {
      await context.close();
    }
  }
};
if (require.main === module)
  (async () => {
    const { chromium } = require('../tool/web_ocr/node_modules/playwright');
    const evidence = path.resolve(process.env.OCR_EVIDENCE_DIR || 'build/web-ocr-diagnostics');
    fs.mkdirSync(evidence, { recursive: true });
    const browser = await chromium.launch({
      headless: true,
      ...(process.env.CHROME_EXECUTABLE ? { executablePath: process.env.CHROME_EXECUTABLE } : {}),
      args: ['--no-sandbox'],
    });
    try {
      await module.exports(browser, process.argv[2] || 'http://127.0.0.1:8084/etiket/', evidence);
    } finally {
      await browser.close();
    }
  })().catch((error) => {
    console.error(`::error title=OCR diagnostics::${String(error).replace(/\n/g, '%0A')}`);
    console.error(error);
    process.exitCode = 1;
  });
