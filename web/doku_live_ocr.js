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
  const before = new RegExp('(?:^|[^\\p{L}\\p{N}])(?:%\\s*(' + number + ')|(' + number + ')\\s*%)\\s*(' + fibers + ')(?![\\p{L}])', 'giu');
  const after = new RegExp('(?:^|[^\\p{L}])(' + fibers + ')\\s*(?:%\\s*(' + number + ')|(' + number + ')\\s*%)', 'giu');

  // Tesseract sometimes separates a printed "80% PAMUK" row into two OCR
  // lines. Recover only literal, isolated tokens in ONE OCR block and ONE
  // horizontal row. This is an unverified yellow hint, not an accepted value.
  function spatialCandidates(lines, width, height) {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
        width <= 0 || height <= 0 || width * height > 48000000 ||
        lines.length < 2 || lines.length > 64) return [];
    const ratios = [], names = [];
    const isolatedPercent = /^(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)$/u;
    const isolatedName = new RegExp('^(?:' + fibers + ')$', 'iu');
    for (let i = 0; i < lines.length; i++) {
      const {text, box} = lines[i];
      if (!box || ![box.x0, box.y0, box.x1, box.y1].every(Number.isFinite) ||
          box.x0 < 0 || box.y0 < 0 || box.x1 <= box.x0 || box.y1 <= box.y0 ||
          box.x1 > width || box.y1 > height) return [];
      const value = text.trim();
      const match = isolatedPercent.exec(value);
      if (match) {
        const percent = Number(match[1] || match[2]);
        if (percent > 0 && percent <= 100) ratios.push({i, percent});
      } else if (isolatedName.test(value)) {
        names.push({i, fiber: value.toLocaleLowerCase('tr')});
      }
    }
    if (!ratios.length || !names.length || ratios.length > 8 ||
        names.length > 8) return [];
    function adjacent(ai, bi) {
      const a = lines[ai].box, b = lines[bi].box;
      const left = a.x0 <= b.x0 ? a : b;
      const right = left === a ? b : a;
      if (left.x1 >= right.x0) return false;
      const ah = a.y1 - a.y0, bh = b.y1 - b.y0;
      const overlap = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      if (overlap < .65 * Math.min(ah, bh) ||
          Math.abs((a.y0 + a.y1 - b.y0 - b.y1) / 2) >
            .35 * Math.max(ah, bh) ||
          right.x0 - left.x1 > Math.min(width * .10, Math.max(ah, bh) * 3)) {
        return false;
      }
      // Intervening or overlapping OCR tokens make the association ambiguous.
      for (let i = 0; i < lines.length; i++) {
        if (i === ai || i === bi) continue;
        const other = lines[i].box;
        const intersects = (p, q) => p.x0 < q.x1 && p.x1 > q.x0 &&
          p.y0 < q.y1 && p.y1 > q.y0;
        if (intersects(other, a) || intersects(other, b)) return false;
        const sameRow = Math.min(other.y1, a.y1, b.y1) -
          Math.max(other.y0, a.y0, b.y0) > 0;
        if (sameRow && other.x0 < right.x0 && other.x1 > left.x1) return false;
      }
      return true;
    }
    const found = [], keys = new Set();
    for (const ratio of ratios) {
      const matches = names.filter(name => adjacent(ratio.i, name.i));
      if (matches.length !== 1) continue;
      const name = matches[0];
      if (ratios.filter(other => adjacent(other.i, name.i)).length !== 1) continue;
      const key = ratio.percent + ':' + name.fiber;
      if (keys.has(key)) return []; // Repeated values cannot be tracked uniquely.
      keys.add(key);
      const a = lines[ratio.i].box, b = lines[name.i].box;
      found.push({percent: ratio.percent, fiber: name.fiber,
        box: {x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0),
          x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1)}});
    }
    return found;
  }

  function extract(data, width, height, sequence, durationMs) {
    const boxes = [], pairBoxes = [], cues = [], pairObservations = [];
    const unique = new Set(), duplicateKeys = new Set();
    let textPresent = false;
    const blocks = Array.isArray(data?.blocks) ? data.blocks.slice(0, 40) : [];
    for (const block of blocks) {
      const blockLines = [];
      for (const paragraph of (block.paragraphs || []).slice(0, 30)) {
        for (const line of (paragraph.lines || []).slice(0, 30)) {
          const value = typeof line.text === 'string' ? line.text : '';
          if (!value.trim()) continue;
          textPresent = true;
          const bb = line.bbox;
          const validBox = bb && [bb.x0, bb.y0, bb.x1, bb.y1].every(Number.isFinite) &&
            bb.x0 >= 0 && bb.y0 >= 0 && bb.x1 > bb.x0 && bb.y1 > bb.y0 &&
            bb.x1 <= width && bb.y1 <= height;
          // Only a visible, retained OCR line can receive a matched-pair box.
          const lineBox = validBox ?
            {x0: bb.x0, y0: bb.y0, x1: bb.x1, y1: bb.y1} : null;
          blockLines.push({text: value, box: lineBox});
          // Only literal percent-marked fiber pairs on the SAME OCR line.
          // Do not infer missing %, section, full-label coverage or correctness.
          // Select a single reading order per line. Running both regexes
          // would invent "20% PAMUK" from "80% PAMUK 20% KETEN".
          const firstRatio = value.search(/(?:%\s*\d{1,3}|\d{1,3}\s*%)/u);
          const firstFiber = value.search(new RegExp(
            '(?:^|[^\\p{L}])(?:' + fibers + ')(?![\\p{L}])', 'iu'));
          if (firstRatio < 0 || firstFiber < 0) {
            // Keep ordinary OCR text visible in gray. Only matched pairs
            // may displace an unrelated line when the overlay budget fills.
            if (lineBox && boxes.length < 24) boxes.push(lineBox);
            continue;
          }
          const ratioFirst = firstRatio <= firstFiber;
          const pattern = ratioFirst ? before : after;
          const fiberIndex = ratioFirst ? 3 : 1;
          const percentIndices = ratioFirst ? [1, 2] : [2, 3];
          {
            let lineHasPair = false;
            const linePairs = [];
            pattern.lastIndex = 0;
            for (const match of value.matchAll(pattern)) {
              const percent = Number(match[percentIndices[0]] || match[percentIndices[1]]);
              const fiber = match[fiberIndex].toLocaleLowerCase('tr');
              if (!(percent > 0 && percent <= 100)) continue;
              lineHasPair = true;
              const key = percent + ':' + fiber;
              if (unique.has(key)) {
                // Two lines claiming the same pair cannot be tracked uniquely.
                duplicateKeys.add(key);
              } else if (cues.length < 8) {
                unique.add(key);
                cues.push({percent, fiber});
                linePairs.push({percent, fiber});
              }
            }
            // Distinguish actual same-line ratio+fiber matches from unrelated
            // OCR text. This geometry is advisory and never verifies a pair.
            if (lineBox) {
              let retained = boxes.length < 24;
              if (!retained && lineHasPair) {
                // Dense care labels can put composition after 24 instruction
                // lines. Prefer a REAL matched line over an unrelated text
                // rectangle, without exceeding the fixed overlay budget.
                // Never evict a previously retained matched-pair line.
                for (let i = boxes.length - 1; i >= 0; i--) {
                  const previous = boxes[i];
                  if (!pairBoxes.some(p => p.x0 === previous.x0 &&
                      p.y0 === previous.y0 && p.x1 === previous.x1 &&
                      p.y1 === previous.y1)) {
                    boxes.splice(i, 1);
                    retained = true;
                    break;
                  }
                }
              }
              if (retained) {
                boxes.push(lineBox);
                if (lineHasPair) {
                  pairBoxes.push(lineBox);
                  for (const pair of linePairs) {
                    pairObservations.push({...pair, box: lineBox});
                  }
                }
              }
            }
          }
        }
      }
      // Spatially split tokens are only advisory; never fill in a missing
      // percentage or fiber. The union box comes from two real OCR boxes.
      for (const candidate of spatialCandidates(blockLines, width, height)) {
        const key = candidate.percent + ':' + candidate.fiber;
        if (unique.has(key)) {
          duplicateKeys.add(key);
          continue;
        }
        if (cues.length >= 8) continue;
        unique.add(key);
        cues.push({percent: candidate.percent, fiber: candidate.fiber});
        let retained = boxes.length < 24;
        if (!retained) {
          for (let i = boxes.length - 1; i >= 0; i--) {
            const previous = boxes[i];
            if (!pairBoxes.some(p => p.x0 === previous.x0 &&
                p.y0 === previous.y0 && p.x1 === previous.x1 &&
                p.y1 === previous.y1)) {
              boxes.splice(i, 1);
              retained = true;
              break;
            }
          }
        }
        if (retained) {
          boxes.push(candidate.box);
          pairBoxes.push(candidate.box);
          pairObservations.push(candidate);
        }
      }
    }
    // Tesseract's raw text is intentionally not returned to the camera UI.
    // Every observation is tied to a literal matched OCR line. A duplicate
    // key or a non-retained/invalid line has no usable temporal geometry.
    // No raw text, photo or video frame is returned.
    return {boxes, pairBoxes, cues,
      pairObservations: pairObservations.filter(p =>
        !duplicateKeys.has(p.percent + ':' + p.fiber)),
      textPresent, width, height, sequence, durationMs};
  }

  function create(onResult, onError) {
    if (!available()) return null;
    let closed = false, busy = false, failed = false, worker = null;
    let initializing = null, lastStarted = -Infinity, sequence = 0, canvas = null;
    // Some cameras keep presenting the same decoded frame after a stream stall.
    // When the browser exposes a real decoded-frame counter, do not run OCR
    // again on that frozen frame or count it as independent stability evidence.
    // Unsupported WebKit implementations keep the existing conservative path;
    // neither path can authorize green or approve an OCR value.
    let lastDecodedFrame = null;
    // On WebKit builds without decoded-frame statistics, use a ONE-SHOT
    // requestVideoFrameCallback to establish that another frame was presented.
    // Never poll every display frame: the OCR budget remains 1 pass / 2 seconds.
    let trackedVideo = null, frameCallbackId = null;
    let presentedFrames = 0, lastSampledPresentedFrames = null;
    function resetFrameTracking() {
      if (trackedVideo && frameCallbackId !== null) {
        try { trackedVideo.cancelVideoFrameCallback?.(frameCallbackId); }
        catch (_) { /* A stopped camera may reject cancellation. */ }
      }
      trackedVideo = null;
      frameCallbackId = null;
      presentedFrames = 0;
      lastSampledPresentedFrames = null;
      lastDecodedFrame = null;
    }
    function watchNextPresentedFrame(video) {
      if (typeof video.requestVideoFrameCallback !== 'function') return false;
      if (frameCallbackId !== null) return true;
      try {
        frameCallbackId = video.requestVideoFrameCallback(() => {
          frameCallbackId = null;
          if (!closed && trackedVideo === video) presentedFrames++;
        });
        return true;
      } catch (_) { return false; }
    }
    // Retry small printed percentages with more of the CAMERA'S OWN pixels,
    // not interpolation. Every third inconclusive frame may use <=2MP;
    // normal frames remain <=1.2MP to bound CPU, memory and battery load.
    let inconclusivePasses = 0;
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
      if (trackedVideo !== video) {
        resetFrameTracking(); // A new camera element has an independent clock.
        trackedVideo = video;
      }
      // OCR sequence numbers prove processing order, NOT independent video frames.
      // Only a strictly advancing browser frame clock can support a stability claim.
      let freshFrame = false;
      let decodedFrame = null;
      try {
        const count = video.getVideoPlaybackQuality?.()?.totalVideoFrames;
        if (Number.isSafeInteger(count) && count > 0) decodedFrame = count;
      } catch (_) { /* Browser does not expose decoded-frame statistics. */ }
      if (decodedFrame !== null) {
        // A camera track renegotiation may reset its counter; equality alone
        // proves that no additional decoded frame has arrived.
        if (lastDecodedFrame !== null && decodedFrame === lastDecodedFrame) return false;
        freshFrame = lastDecodedFrame !== null && decodedFrame > lastDecodedFrame;
        // Counter rollback (track renegotiation) allows OCR, but cannot prove
        // an independent frame until the counter advances again.
        lastDecodedFrame = decodedFrame;
      } else if (watchNextPresentedFrame(video)) {
        // The first observation is advisory. Every later one needs a new
        // presented frame, not just an elapsed throttle interval.
        if (lastSampledPresentedFrames !== null &&
            lastSampledPresentedFrames === presentedFrames) return false;
        freshFrame = lastSampledPresentedFrames !== null &&
          presentedFrames > lastSampledPresentedFrames;
        lastSampledPresentedFrames = presentedFrames;
      } else {
        // Older WebKit and unsupported camera mocks keep the existing local
        // gray/yellow fallback. This path never authorizes green.
        lastDecodedFrame = null;
        lastSampledPresentedFrames = null;
      }
      busy = true;
      lastStarted = Date.now();
      const id = ++sequence;
      const started = Date.now();
      try {
        // The 1200px preview can erase tiny '%' glyphs even when the camera
        // supplies a larger native video frame. After two OCR passes without
        // a retained literal percent+fiber box, try ONE bounded detail pass.
        // Do not upscale, change PSM, infer missing text, or treat it as proof.
        const detail = inconclusivePasses >= 2 && id % 3 === 0 &&
          Math.max(video.videoWidth, video.videoHeight) > 1200;
        const longSide = detail ? 1600 : 1200;
        const pixelBudget = detail ? 2000000 : 1200000;
        const scale = Math.min(1, longSide / Math.max(video.videoWidth, video.videoHeight),
          Math.sqrt(pixelBudget / (video.videoWidth * video.videoHeight)));
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
        if (!closed) {
          const reading = extract(output?.data, width, height, id, Date.now() - started);
          reading.freshFrame = freshFrame; // No raw frame/time metadata leaves the worker.
          inconclusivePasses = reading.pairObservations.length
            ? 0 : Math.min(3, inconclusivePasses + 1);
          onResult(reading); // Still only unverified yellow/gray camera hints.
        }
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
      resetFrameTracking();
      if (canvas) { canvas.width = canvas.height = 0; canvas = null; }
      if (worker) { const old = worker; worker = null; Promise.resolve(old.terminate()).catch(() => {}); }
      // An in-flight createWorker terminates itself after resolving if closed.
      // No result callback can run after stop.
    }
    return Object.freeze({sample, stop});
  }
  return Object.freeze({get available() { return available(); }, create, extract});
});
