'use strict';
// D4.2: compare fractional crop resampling AND 2x interpolation on generated labels.
// This is a paired Chromium/Tesseract WASM study, NOT a real-photo benchmark.
// Neither variant changes the production OCR proposal or user approval.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('../tool/web_ocr/node_modules/playwright');
const {textDistance, containsExactPair} = require('./ocr_benchmark_metrics.cjs');

const base = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
const out = path.resolve('build/web-ocr-evidence');
const truth = '80% PAMUK\n20% POLYESTER';
const pairs = [{percent:'80', fiber:'PAMUK'}, {percent:'20', fiber:'POLYESTER'}];
const cases = [
  {id:'small-dark', font:22, ink:'#292929', background:'#f4f3ed'},
  {id:'small-faint', font:22, ink:'#77736d', background:'#e8e5dd'},
  {id:'small-defocus', font:22, ink:'#292929', background:'#f4f3ed', blurPx:1.25}
];

async function main() {
  const browser = await chromium.launch({headless:true, args:['--no-sandbox']});
  const context = await browser.newContext({locale:'tr-TR', viewport:{width:390,height:844}});
  const page = await context.newPage();
  const requests = [], results = [];
  page.on('request', request => requests.push(request.method()));
  try {
    await page.goto(base, {waitUntil:'networkidle'});
    await page.evaluate(async () => {
      const assets = new URL('./ocr/', location.href);
      window.__cropPixelWorker = await Tesseract.createWorker(['tur','eng'], 1, {
        workerPath:new URL('worker.min.js', assets).href,
        corePath:new URL('core/', assets).href,
        langPath:new URL('lang/', assets).href.replace(/\/$/, ''),
        workerBlobURL:false, gzip:true, cachePath:'doku-ocr-6-best-int-v1'
      });
      await window.__cropPixelWorker.setParameters({preserve_interword_spaces:'1'});
    });
    for (const fixture of cases) {
      const sample = await page.evaluate(async f => {
        const source = document.createElement('canvas');
        source.width = 1200; source.height = 700;
        const s = source.getContext('2d');
        s.fillStyle = f.background; s.fillRect(0,0,source.width,source.height);
        // Fixed texture is identical in both arms, including the printed ink.
        s.strokeStyle = '#c9c8c1'; s.lineWidth = 1;
        for (let y=20; y<700; y+=11) {
          s.beginPath(); s.moveTo(0,y); s.lineTo(1200,y+2); s.stroke();
        }
        s.fillStyle = f.ink; s.font = 'bold ' + f.font + 'px Arial';
        s.fillText('80% PAMUK', 260, 265);
        s.fillText('20% POLYESTER', 260, 340);
        // Defocus the entire generated frame, not only the printed text.
        let frame = source;
        if (f.blurPx) {
          const blurred = document.createElement('canvas');
          blurred.width = source.width; blurred.height = source.height;
          const bc = blurred.getContext('2d');
          bc.filter = 'blur(' + f.blurPx + 'px)';
          bc.drawImage(source, 0, 0);
          frame = blurred;
        }
        const img = new Image();
        img.src = frame.toDataURL('image/png');
        await img.decode();
        // The two arms have identical integer output dimensions, input
        // pixels, crop size and PSM. ONLY subpixel translation differs.
        const render = (fractional) => {
          const c = document.createElement('canvas');
          c.width = 730; c.height = 240;
          const g = c.getContext('2d', {willReadFrequently:true});
          g.imageSmoothingEnabled = fractional;
          g.drawImage(img, -(fractional ? 220.49 : 220), -(fractional ? 180.49 : 180));
          return {canvas:c, rgba:g.getImageData(0,0,c.width,c.height).data};
        };
        const aligned = render(false), subpixel = render(true);
        // Independent 2x interpolation control: identical native crop pixels.
        // The production bridge enlarges small crops; this isolates that step
        // without silently choosing the best OCR text or altering the UI.
        const enlarged = document.createElement('canvas');
        enlarged.width = aligned.canvas.width * 2;
        enlarged.height = aligned.canvas.height * 2;
        const ec = enlarged.getContext('2d', {willReadFrequently:true});
        ec.imageSmoothingEnabled = true;
        ec.imageSmoothingQuality = 'high';
        ec.drawImage(aligned.canvas, 0, 0, enlarged.width, enlarged.height);
        const upscaledRgba = ec.getImageData(0, 0, enlarged.width, enlarged.height).data;
        let upscaleChanged = 0;
        for (let y = 0; y < aligned.canvas.height; y++) for (let x = 0; x < aligned.canvas.width; x++) {
          const p = (y * aligned.canvas.width + x) * 4;
          const q = ((2 * y) * enlarged.width + 2 * x) * 4;
          if (aligned.rgba[p] !== upscaledRgba[q] ||
              aligned.rgba[p+1] !== upscaledRgba[q+1] ||
              aligned.rgba[p+2] !== upscaledRgba[q+2]) upscaleChanged++;
        }
        let changed = 0;
        for (let i=0; i<aligned.rgba.length; i+=4) {
          if (aligned.rgba[i] !== subpixel.rgba[i] ||
              aligned.rgba[i+1] !== subpixel.rgba[i+1] ||
              aligned.rgba[i+2] !== subpixel.rgba[i+2]) changed++;
        }
        const url = async canvas => {
          const blob = await new Promise((resolve,reject) =>
            canvas.toBlob(b => b ? resolve(b) : reject(Error('crop encode failed')), 'image/png'));
          return URL.createObjectURL(blob);
        };
        return {aligned:await url(aligned.canvas), subpixel:await url(subpixel.canvas),
          upscaled:await url(enlarged), changedPixels:changed,
          upscaleChangedPixels:upscaleChanged,
          width:aligned.canvas.width, height:aligned.canvas.height};
      }, fixture);
      assert.deepEqual([sample.width,sample.height],[730,240]);
      assert.ok(sample.changedPixels>0, 'The paired resampling arms must differ in pixels');
      assert.ok(sample.upscaleChangedPixels>0, 'The 2x interpolation arm must change source pixels');
      try {
        for (const variant of ['aligned','subpixel','upscaled']) {
          for (const psm of [3,6,11]) {
            const start = Date.now();
            const text = await page.evaluate(async arg => {
              await window.__cropPixelWorker.setParameters({
                tessedit_pageseg_mode:String(arg.psm)
              });
              const blob = await (await fetch(arg.url)).blob();
              return (await window.__cropPixelWorker.recognize(blob, {}, {text:true})).data.text;
            }, {url:sample[variant], psm});
            assert.equal(typeof text, 'string');
            const distance = textDistance(truth, text);
            results.push({
              fixture:fixture.id, variant, psm,
              exactPairs:pairs.filter(pair => containsExactPair(text,pair)).length,
              referencePairs:pairs.length,
              cer:distance.characterEdits / distance.referenceCharacters,
              wer:distance.wordEdits / distance.referenceWords,
              latencyMs:Date.now()-start,
              changedPixels:sample.changedPixels,
              upscaleChangedPixels:sample.upscaleChangedPixels
            });
          }
        }
      } finally {
        await page.evaluate(urls => urls.forEach(url => URL.revokeObjectURL(url)),
          [sample.aligned,sample.subpixel,sample.upscaled]);
      }
    }
    assert.equal(results.length,27);
    assert.ok(requests.every(method => method==='GET' || method==='HEAD'),
      'Generated image and OCR text must not be uploaded');
    const summary = [];
    for (const fixture of cases) for (const psm of [3,6,11]) {
      const a=results.find(r=>r.fixture===fixture.id && r.psm===psm && r.variant==='aligned');
      const b=results.find(r=>r.fixture===fixture.id && r.psm===psm && r.variant==='subpixel');
      const c=results.find(r=>r.fixture===fixture.id && r.psm===psm && r.variant==='upscaled');
      summary.push({fixture:fixture.id,psm,
        alignedExact:a.exactPairs,subpixelExact:b.exactPairs,upscaledExact:c.exactPairs,
        alignedCer:a.cer,subpixelCer:b.cer,upscaledCer:c.cer,
        alignedWer:a.wer,subpixelWer:b.wer,upscaledWer:c.wer,
        deltaExact:a.exactPairs-b.exactPairs,
        deltaUpscaledExact:c.exactPairs-a.exactPairs});
      console.log('SYNTHETIC '+fixture.id+' PSM'+psm+
        ' pixel-aligned '+a.exactPairs+'/2 vs subpixel '+b.exactPairs+
        '/2 vs 2x '+c.exactPairs+'/2');
    }
    fs.mkdirSync(out,{recursive:true});
    fs.writeFileSync(path.join(out,'crop-pixel-resampling-ab.json'),JSON.stringify({
      kind:'SYNTHETIC ONLY', realPhotoCount:0, realAccuracy:null,
      engine:'Chromium + local Tesseract.js WASM tur/eng',
      caveat:'Paired fractional-crop and 2x interpolation experiments only; not a real-phone accuracy claim',
      selection:'No OCR hypothesis is selected, repaired, or accepted',
      summary,results
    },null,2));
  } finally {
    await page.evaluate(async () => {
      if (window.__cropPixelWorker) await window.__cropPixelWorker.terminate();
    }).catch(()=>{});
    await context.close();
    await browser.close();
  }
}
main().catch(error => {
  console.error('::error title=OCR crop resampling A/B::'+String(error));
  process.exitCode=1;
});
