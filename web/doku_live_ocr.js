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
  // A visible number next to a fiber without the printed % is NOT a pair.
  // It can, however, justify one bounded native-pixel detail retry.
  const missingPercent = new RegExp('(?:^|\\s)' + number + '\\s+(?:' + fibers + ')(?![\\p{L}])|(?:^|\\s)(?:' + fibers + ')\\s+' + number + '(?![\\p{L}\\p{N}%])', 'iu');

  // Select the UNIQUE maximum set of non-overlapping literal pairs.
  // Greedy regex order can assign "PAMUK 80% KETEN" to either fiber.
  // Ambiguity fails closed: no yellow pair, no matched geometry or stability.
  // This is a bounded live hint only, never an accepted scan or green signal.
  function literalPairsFromLine(value) {
    if (value.length > 512) return [];
    const candidates = [];
    for (const [pattern, ratioBefore] of [[before, true], [after, false]]) {
      pattern.lastIndex = 0;
      for (const match of value.matchAll(pattern)) {
        const percent = Number(ratioBefore ?
          (match[1] || match[2]) : (match[2] || match[3]));
        const fiber = (ratioBefore ? match[3] : match[1])
          .toLocaleLowerCase('tr');
        if (percent > 0 && percent <= 100) {
          candidates.push({start: match.index,
            end: match.index + match[0].length, percent, fiber});
        }
        if (candidates.length > 32) return [];
      }
    }
    if (!candidates.length) return [];
    candidates.sort((a, b) => a.end - b.end || a.start - b.start);
    const n = candidates.length;
    const score = Array(n + 1).fill(0);
    const ways = Array(n + 1).fill(1);
    const previous = Array(n + 1).fill(0);
    const taken = Array(n + 1).fill(false);
    for (let i = 1; i <= n; i++) {
      const current = candidates[i - 1];
      let compatible = i - 1;
      while (compatible > 0 &&
          candidates[compatible - 1].end > current.start) compatible--;
      const withCurrent = score[compatible] + 1;
      const withoutCurrent = score[i - 1];
      if (withCurrent > withoutCurrent) {
        score[i] = withCurrent;
        ways[i] = ways[compatible];
        previous[i] = compatible;
        taken[i] = true;
      } else if (withCurrent < withoutCurrent) {
        score[i] = withoutCurrent;
        ways[i] = ways[i - 1];
        previous[i] = i - 1;
      } else {
        score[i] = withCurrent;
        ways[i] = 2;
      }
    }
    if (ways[n] !== 1 || score[n] > 8) return [];
    const selected = [];
    for (let i = n; i > 0; i = previous[i]) {
      if (taken[i]) selected.push(candidates[i - 1]);
    }
    return selected.reverse().sort((a, b) => a.start - b.start);
  }

  // Tesseract sometimes separates a printed "80% PAMUK" row into
  // isolated OCR tokens, even across blocks. Recover only literal tokens
  // on the same physical row with globally unique geometry. This remains
  // an unverified yellow hint, never an accepted value.
  function spatialCandidates(lines, width, height) {
    if (!Number.isFinite(width) || !Number.isFinite(height) ||
        width <= 0 || height <= 0 || width * height > 48000000 ||
        lines.length < 2 || lines.length > 256) return [];
    const ratios = [], names = [], digits = [], marks = [], ignored = new Set();
    const isolatedPercent = /^(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)$/u;
    const isolatedName = new RegExp('^(?:' + fibers + ')$', 'iu');
    const possibleFiber = new RegExp(
      '(?:^|[^\\p{L}])(?:' + fibers + ')(?![\\p{L}])', 'iu');
    for (let i = 0; i < lines.length; i++) {
      const {text, box} = lines[i];
      const value = text.trim();
      if (!box || ![box.x0, box.y0, box.x1, box.y1].every(Number.isFinite) ||
          box.x0 < 0 || box.y0 < 0 || box.x1 <= box.x0 || box.y1 <= box.y0 ||
          box.x1 > width || box.y1 > height) {
        // Unboxed unrelated care instructions must not hide real split pairs.
        // An unboxed possible percentage/fiber could compete: fail closed.
        if (value.includes('%') || possibleFiber.test(value)) return [];
        ignored.add(i);
        continue;
      }
      const match = isolatedPercent.exec(value);
      if (match) {
        const percent = Number(match[1] || match[2]);
        if (percent > 0 && percent <= 100)
          ratios.push({i, percent, box, members: [i]});
      } else if (isolatedName.test(value)) {
        names.push({i, fiber: value.toLocaleLowerCase('tr'), box});
      } else if (/^(?:100|[1-9]?[0-9])$/.test(value)) {
        digits.push({i, percent: Number(value), box});
      } else if (value === '%') {
        marks.push({i, box});
      }
    }
    // Tesseract can isolate the ACTUALLY PRINTED percent glyph from "80".
    // Recover only a tightly adjacent, same-row digit + '%' with unique
    // ownership. A bare number alone NEVER becomes a percentage.
    function markAdjacent(digit, mark) {
      const a = digit.box, b = mark.box;
      const ah = a.y1 - a.y0, bh = b.y1 - b.y0;
      const overlap = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      const horizontalGap = Math.max(a.x0, b.x0) - Math.min(a.x1, b.x1);
      return overlap >= .6 * Math.min(ah, bh) &&
        Math.abs((a.y0 + a.y1 - b.y0 - b.y1) / 2) <= .4 * Math.max(ah, bh) &&
        horizontalGap >= -.15 * Math.min(a.x1 - a.x0, b.x1 - b.x0) &&
        horizontalGap <= Math.min(width * .015, Math.max(4, .55 * Math.max(ah, bh)));
    }
    for (const digit of digits) {
      const possible = marks.filter(mark => markAdjacent(digit, mark));
      if (possible.length > 1) return []; // One number, two glyphs.
      if (possible.length !== 1) continue;
      const mark = possible[0];
      if (digits.filter(other => markAdjacent(other, mark)).length !== 1)
        return []; // One glyph, competing numbers.
      ratios.push({i: -1, percent: digit.percent,
        box: {x0: Math.min(digit.box.x0, mark.box.x0),
          y0: Math.min(digit.box.y0, mark.box.y0),
          x1: Math.max(digit.box.x1, mark.box.x1),
          y1: Math.max(digit.box.y1, mark.box.y1)},
        members: [digit.i, mark.i]});
    }
    if (!ratios.length || !names.length || ratios.length > 8 ||
        names.length > 8) return [];
    function adjacent(ratio, name) {
      const a = ratio.box, b = name.box;
      const consumed = new Set([...ratio.members, name.i]);
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
        if (consumed.has(i) || ignored.has(i)) continue;
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
      const matches = names.filter(name => adjacent(ratio, name));
      if (matches.length !== 1) continue;
      const name = matches[0];
      if (ratios.filter(other => adjacent(other, name)).length !== 1) continue;
      const key = ratio.percent + ':' + name.fiber;
      if (keys.has(key)) return []; // Repeated values cannot be tracked uniquely.
      keys.add(key);
      const a = ratio.box, b = name.box;
      found.push({percent: ratio.percent, fiber: name.fiber,
        box: {x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0),
          x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1)}});
    }
    return found;
  }


  // Cross-BLOCK ambiguity for already printed inline pairs. A rival token
  // at the same physical row must not make a wrong pair look stable.
  // A suspicious line requests a higher-detail LOCAL OCR retry; never guess.
  function inlineCrossBlockConflict(candidate, lines, width) {
    const fiberToken = new RegExp('(?:^|[^\\p{L}])(?:' + fibers + ')(?![\\p{L}])', 'iu');
    const ratioToken = /(?:%\s*(?:100|[1-9]?[0-9])|(?:100|[1-9]?[0-9])\s*%)/u;
    const bareToken = /^(?:100|[1-9]?[0-9]|%)$/u;
    const a = candidate.box;
    for (const other of lines) {
      if (other.blockIndex === candidate.blockIndex) continue;
      const text = other.text.trim();
      if (!fiberToken.test(text) && !ratioToken.test(text) &&
          !bareToken.test(text)) continue;
      const b = other.box;
      // A possible competing composition token with unknown position is
      // unsafe, not evidence that it belongs to another label row.
      if (!b) return true;
      const ah = a.y1 - a.y0, bh = b.y1 - b.y0;
      const verticalOverlap = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      if (verticalOverlap < .5 * Math.min(ah, bh) ||
          Math.abs((a.y0 + a.y1 - b.y0 - b.y1) / 2) >
            .5 * Math.max(ah, bh)) continue;
      const overlaps = a.x0 < b.x1 && a.x1 > b.x0 &&
        a.y0 < b.y1 && a.y1 > b.y0;
      // Two complete, nonoverlapping printed pairs may share one row.
      if (!overlaps && literalPairsFromLine(text).length > 0) continue;
      const gap = Math.max(0, a.x0 - b.x1, b.x0 - a.x1);
      if (gap <= Math.min(width * .05, Math.max(ah, bh) * 2)) return true;
    }
    return false;
  }

  function extract(data, width, height, sequence, durationMs) {
    const boxes = [], pairBoxes = [], cues = [], pairObservations = [];
    const unique = new Set(), duplicateKeys = new Set(), inlineCandidates = [];
    let textPresent = false, detailNeeded = false;
    const blocks = Array.isArray(data?.blocks) ? data.blocks.slice(0, 40) : [];
    // A dense care label can have composition AFTER 30 Tesseract lines or
    // paragraphs. Keep scanning real OCR lines, not just the first 30, while
    // bounding per-block spatial matching and total live-preview work.
    // These are still unverified candidates; never infer missing tokens.
    let remainingLines = 512;
    // Keep at most 257 lines: the cross-block matcher rejects >256 rather
    // than silently ignoring a competing token from a dense care label.
    const crossBlockLines = [];
    for (const [blockIndex, block] of blocks.entries()) {
      if (remainingLines <= 0) break;
      let blockRemaining = Math.min(256, remainingLines);
      for (const paragraph of (block.paragraphs || []).slice(0, 256)) {
        for (const line of (paragraph.lines || []).slice(0, blockRemaining)) {
          blockRemaining--;
          remainingLines--;
          const value = typeof line.text === 'string' ? line.text : '';
          if (!value.trim()) continue;
          textPresent = true;
          // A partly read composition line can coexist with a correct pair.
          // Do not let that first pair suppress a higher-detail retry for the
          // still-unreadable small percentage. Never infer the missing '%'.
          if (missingPercent.test(value)) detailNeeded = true;
          const bb = line.bbox;
          const validBox = bb && [bb.x0, bb.y0, bb.x1, bb.y1].every(Number.isFinite) &&
            bb.x0 >= 0 && bb.y0 >= 0 && bb.x1 > bb.x0 && bb.y1 > bb.y0 &&
            bb.x1 <= width && bb.y1 <= height;
          // Only a visible, retained OCR line can receive a matched-pair box.
          const lineBox = validBox ?
            {x0: bb.x0, y0: bb.y0, x1: bb.x1, y1: bb.y1} : null;
          if (crossBlockLines.length <= 256) {
            crossBlockLines.push({text: value, box: lineBox, blockIndex});
          }
          // Literal printed pairs only; ambiguous token assignment fails closed.
          const matches = literalPairsFromLine(value);

          // Even a recognized pair can be tiny at preview resolution. Use
          // source camera pixels for an occasional retry, never interpolation.
          if (lineBox && matches.length &&
              lineBox.y1 - lineBox.y0 < Math.max(12, height * .022)) {
            detailNeeded = true;
          }
          {
            let lineHasPair = false;
            const linePairs = [];
            for (const {percent, fiber} of matches) {
              lineHasPair = true;
              if (lineBox) inlineCandidates.push({percent, fiber, box: lineBox, blockIndex});
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
        if (blockRemaining <= 0) break;
      }
    }
    // Resolve ALL isolated percentage/fiber tokens in one global geometry
    // pass. Matching within each block first could falsely retain "80% PAMUK"
    // when another Tesseract block contains an equally adjacent "KETEN" or
    // competing ratio. Never count a partial, ambiguous match as a stable cue.
    // If the bounded global line set is too large, fail closed rather than
    // accepting a candidate before inspecting competing blocks.
    for (const candidate of spatialCandidates(crossBlockLines, width, height)) {
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
    // Inline pairs also need GLOBAL cross-block conflict inspection. Without
    // this, "80% PAMUK" in one Tesseract block and rival "KETEN" in another
    // could be shown as a stable match. If inspection is truncated, fail closed.
    const incompleteInspection = (Array.isArray(data?.blocks) &&
      data.blocks.length > blocks.length) || remainingLines <= 0 ||
      crossBlockLines.length > 256;
    const unsafeInlineKeys = new Set();
    for (const candidate of inlineCandidates) {
      if (incompleteInspection ||
          inlineCrossBlockConflict(candidate, crossBlockLines, width)) {
        unsafeInlineKeys.add(candidate.percent + ':' + candidate.fiber);
      }
    }
    if (unsafeInlineKeys.size) detailNeeded = true;
    const safeKey = p => !unsafeInlineKeys.has(p.percent + ':' + p.fiber);
    const safeObservations = pairObservations.filter(p =>
      safeKey(p) && !duplicateKeys.has(p.percent + ':' + p.fiber));
    const safePairBoxes = pairBoxes.filter(b =>
      !inlineCandidates.some(p => !safeKey(p) &&
        p.box.x0 === b.x0 && p.box.y0 === b.y0 &&
        p.box.x1 === b.x1 && p.box.y1 === b.y1) ||
      safeObservations.some(p => p.box.x0 === b.x0 && p.box.y0 === b.y0 &&
        p.box.x1 === b.x1 && p.box.y1 === b.y1));
    // No raw OCR, photo or video frame is returned. The conflicting hint is
    // yellow partial text only, and the next OCR may retry with source pixels.
    return {boxes, pairBoxes: safePairBoxes, cues: cues.filter(safeKey),
      pairObservations: safeObservations,
      detailNeeded, textPresent, width, height, sequence, durationMs};
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
          inconclusivePasses = reading.pairObservations.length && !reading.detailNeeded
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
