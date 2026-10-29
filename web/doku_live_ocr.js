/* Doku ephemeral live Web OCR. Never persists frames, text, EXIF or user edits.
 * Live results are unverified visual hints, never an accepted scan.
 */
(function (root, factory) {
  'use strict';
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.dokuLiveOcr = api;
})(globalThis, function (root) {
  'use strict';
  const available = () => !!(root.isSecureContext && root.Tesseract?.createWorker &&
    root.Worker && root.document?.createElement);
  const fibers = 'pamuk|cotton|keten|linen|polyester|poliester|viskon|viskoz|viscose|elastan|elastane|spandex|yun|yün|wool|poliamid|polyamide|nylon|naylon|akrilik|acrylic|ipek|silk|modal|liyosel|lyocell';
  const number = '(?:100|[1-9]?[0-9])';
  const before = new RegExp('(?:%\\s*(' + number + ')|(' + number + ')\\s*%)\\s*(' + fibers + ')(?![\\p{L}])', 'giu');
  const after = new RegExp('(?:^|[^\\p{L}])(' + fibers + ')\\s*(?:%\\s*(' + number + ')|(' + number + ')\\s*%)', 'giu');

  function extract(data, width, height, sequence, durationMs) {
    const boxes = [], cues = [], unique = new Set();
    let textPresent = false;
    const blocks = Array.isArray(data?.blocks) ? data.blocks.slice(0, 40) : [];
    for (const block of blocks) {
      for (const paragraph of (block.paragraphs || []).slice(0, 30)) {
        for (const line of (paragraph.lines || []).slice(0, 30)) {
          const value = typeof line.text === 'string' ? line.text : '';
          if (!value.trim()) continue;
          textPresent = true;
          const bb = line.bbox;
          if (bb && [bb.x0, bb.y0, bb.x1, bb.y1].every(Number.isFinite) &&
              bb.x0 >= 0 && bb.y0 >= 0 && bb.x1 > bb.x0 && bb.y1 > bb.y0 &&
              bb.x1 <= width && bb.y1 <= height && boxes.length < 24) {
            boxes.push({x0: bb.x0, y0: bb.y0, x1: bb.x1, y1: bb.y1});
          }
          // Only literal percent-marked fiber pairs on the SAME OCR line.
          // Do not infer missing %, section, full-label coverage or correctness.
          // Select a single reading order per line. Running both regexes
          // would invent "20% PAMUK" from "80% PAMUK 20% KETEN".
          const firstRatio = value.search(/(?:%\\s*\\d{1,3}|\\d{1,3}\\s*%)/u);
          const firstFiber = value.search(new RegExp(
            '(?:^|[^\\\\p{L}])(?:' + fibers + ')(?![\\\\p{L}])', 'iu'));
          if (firstRatio < 0 || firstFiber < 0) continue;
          const ratioFirst = firstRatio <= firstFiber;
          const pattern = ratioFirst ? before : after;
          const fiberIndex = ratioFirst ? 3 : 1;
          const percentIndices = ratioFirst ? [1, 2] : [2, 3];
          {
            pattern.lastIndex = 0;
            for (const match of value.matchAll(pattern)) {
              const percent = Number(match[percentIndices[0]] || match[percentIndices[1]]);
              const fiber = match[fiberIndex].toLocaleLowerCase('tr');
              if (!(percent > 0 && percent <= 100)) continue;
              const key = percent + ':' + fiber;
              if (!unique.has(key) && cues.length < 8) {
                unique.add(key);
                cues.push({percent, fiber});
              }
            }
          }
        }
      }
    }
    // Tesseract's raw text is intentionally not returned to the camera UI.
    return {boxes, cues, textPresent, width, height, sequence, durationMs};
  }

  function create(onResult, onError) {
    if (!available()) return null;
    let closed = false, busy = false, failed = false, worker = null;
    let initializing = null, lastStarted = -Infinity, sequence = 0, canvas = null;
    const base = new URL('ocr/', root.document.baseURI);
    async function engine() {
      if (worker) return worker;
      if (!initializing) {
        initializing = root.Tesseract.createWorker(['tur', 'eng'], 1, {
          workerPath: new URL('worker.min.js', base).href,
          corePath: new URL('core/', base).href,
          langPath: new URL('lang/', base).href.replace(/\/$/, ''),
          workerBlobURL: false, gzip: true,
          cachePath: 'doku-ocr-6-best-int-v1', cacheMethod: 'write'
        }).then(async created => {
          if (closed) { await created.terminate(); return null; }
          await created.setParameters({tessedit_pageseg_mode: '6'});
          if (closed) { await created.terminate(); return null; }
          worker = created;
          return created;
        });
      }
      return initializing;
    }
    async function sample(video) {
      if (closed || busy || failed || !video || video.readyState < 2 ||
          !video.videoWidth || !video.videoHeight ||
          Date.now() - lastStarted < 2000) return false;
      busy = true;
      lastStarted = Date.now();
      const id = ++sequence;
      const started = Date.now();
      try {
        const scale = Math.min(1, 1200 / Math.max(video.videoWidth, video.videoHeight),
          Math.sqrt(1200000 / (video.videoWidth * video.videoHeight)));
        const width = Math.max(1, Math.round(video.videoWidth * scale));
        const height = Math.max(1, Math.round(video.videoHeight * scale));
        canvas = root.document.createElement('canvas');
        canvas.width = width; canvas.height = height;
        const context = canvas.getContext('2d');
        if (!context) throw Error('canvas');
        context.drawImage(video, 0, 0, width, height);
        const current = await engine();
        if (!current || closed) return true;
        const output = await current.recognize(canvas, {}, {text: true, blocks: true});
        if (!closed) onResult(extract(output?.data, width, height, id, Date.now() - started));
      } catch (_) {
        if (!closed) {
          failed = true; // Fail closed; keep camera/still/gallery usable.
          onError?.();
        }
      } finally {
        if (canvas) { canvas.width = canvas.height = 0; canvas = null; }
        busy = false;
      }
      return true;
    }
    function stop() {
      closed = true;
      if (canvas) { canvas.width = canvas.height = 0; canvas = null; }
      if (worker) { const old = worker; worker = null; Promise.resolve(old.terminate()).catch(() => {}); }
      // An in-flight createWorker terminates itself after resolving if closed.
      // No result callback can run after stop.
    }
    return Object.freeze({sample, stop});
  }
  return Object.freeze({get available() { return available(); }, create, extract});
});
