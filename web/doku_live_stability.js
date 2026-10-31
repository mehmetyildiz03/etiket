/* Ephemeral consistency for local OCR hints. No text, frame, EXIF or edits persist.
 * Green is intentionally disabled until independent full-label coverage is validated.
 */
(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.dokuLiveStability = api;
})(globalThis, function () {
  'use strict';
  const STALE_MS = 6000;
  const MAX_GAP_MS = 5000;
  // A delayed OCR result describes an old video frame, not the current preview.
  const MAX_OCR_LATENCY_MS = 6000;
  const MAX_DRIFT = 0.15;

  // Advisory only: visible OCR line geometry is NOT full-label coverage.
  // Detect text touching the camera frame or text too small to inspect.
  function geometryHint(reading) {
    if (!reading || reading.stale || !Array.isArray(reading.boxes) ||
        !Number.isFinite(reading.width) || reading.width <= 0 ||
        !Number.isFinite(reading.height) || reading.height <= 0) return null;
    const boxes = reading.boxes.filter(b => b &&
      [b.x0, b.y0, b.x1, b.y1].every(Number.isFinite) &&
      b.x0 >= 0 && b.y0 >= 0 && b.x1 > b.x0 && b.y1 > b.y0 &&
      b.x1 <= reading.width && b.y1 <= reading.height);
    if (!boxes.length) return null;
    const marginX = reading.width * 0.018;
    const marginY = reading.height * 0.018;
    if (boxes.some(b => b.x0 <= marginX || b.y0 <= marginY ||
        b.x1 >= reading.width - marginX ||
        b.y1 >= reading.height - marginY)) return 'edgeText';
    const heights = boxes.map(b => (b.y1 - b.y0) / reading.height)
      .sort((a, b) => a - b);
    if (heights[Math.floor(heights.length / 2)] < 0.02) return 'smallText';
    return null;
  }

  // Compare EACH literal percent+fiber pair in OCR-image coordinates.
  // A stable overall center can hide swapped or wandering individual lines.
  // This is advisory-only; it cannot authorize green or an accepted value.
  function pairGeometryAgrees(previous, current) {
    if (!previous || !current || !previous.size ||
        previous.size !== current.size) return false;
    for (const [key, b] of current) {
      const a = previous.get(key);
      if (!a) return false;
      const aw = a.x1 - a.x0, ah = a.y1 - a.y0;
      const bw = b.x1 - b.x0, bh = b.y1 - b.y0;
      if (!(aw > 0 && ah > 0 && bw > 0 && bh > 0) ||
          bw / aw < .67 || bw / aw > 1.5 ||
          bh / ah < .67 || bh / ah > 1.5 ||
          Math.hypot((a.x0 + a.x1 - b.x0 - b.x1) / 2,
            (a.y0 + a.y1 - b.y0 - b.y1) / 2) > .06) return false;
      const overlapW = Math.max(0, Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0));
      const overlapH = Math.max(0, Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0));
      const intersection = overlapW * overlapH;
      const union = aw * ah + bw * bh - intersection;
      if (!(union > 0 && intersection / union >= .35)) return false;
    }
    return true;
  }

  function create() {
    let lastSequence = -1, lastTime = -Infinity, fingerprint = '',
      center = null, pairGeometry = null, frameAspect = null,
      stableFrames = 0, observation = null, moved = false;
    function clear() {
      lastSequence = -1; lastTime = -Infinity; fingerprint = '';
      center = null; pairGeometry = null; frameAspect = null;
      stableFrames = 0; observation = null; moved = false;
    }
    function view(now) {
      if (!Number.isFinite(now) || now - lastTime > STALE_MS || now < lastTime) {
        clear();
        return {cues: [], boxes: [], pairBoxes: [], textPresent: false, stableFrames: 0,
          moved: false, freshFrame: false, stale: true, level: 'gray', sequence: -1};
      }
      return {cues: observation.cues, boxes: observation.boxes,
        pairBoxes: observation.pairBoxes,
        width: observation.width, height: observation.height, sequence: lastSequence,
        textPresent: observation.textPresent, stableFrames, moved,
        freshFrame: observation.freshFrame, stale: false, level: observation.textPresent ? 'yellow' : 'gray'};
    }
    function observe(next, now) {
      if (!next || !Number.isSafeInteger(next.sequence) ||
          !Number.isFinite(now) || next.sequence <= lastSequence) return view(now);
      // The OCR result describes the video pixels sampled BEFORE the worker
      // finished, not the camera view at callback time. Age hints from their
      // capture time so a 5.9s OCR cannot stay on-screen for another 6s.
      const duration = next.durationMs === undefined ? 0 : next.durationMs;
      if (!Number.isFinite(duration) || duration < 0 ||
          duration > MAX_OCR_LATENCY_MS || duration >= STALE_MS) {
        clear(); // Never show a too-old frame or keep its overlay boxes.
        return view(now);
      }
      const sampledAt = now - duration;
      if (!Number.isFinite(sampledAt)) {
        clear();
        return view(now);
      }
      // A later callback may describe an EARLIER frame. Do not let it replace
      // newer evidence or increase temporal stability.
      if (sampledAt < lastTime) return view(now);
      if (sampledAt - lastTime > MAX_GAP_MS) {
        fingerprint = ''; center = null; pairGeometry = null; stableFrames = 0;
      }
      const nextAspect = Number.isFinite(next.width) && next.width > 0 &&
        Number.isFinite(next.height) && next.height > 0
        ? next.width / next.height : null;
      if (frameAspect !== null && (nextAspect === null ||
          Math.abs(nextAspect / frameAspect - 1) > .025)) {
        // Camera rotation/stream resize invalidates cross-frame agreement.
        fingerprint = ''; center = null; pairGeometry = null; stableFrames = 0;
      }
      frameAspect = nextAspect;
      lastSequence = next.sequence;
      const cues = Array.isArray(next.cues) ? next.cues.filter(c =>
        Number.isInteger(c.percent) && c.percent > 0 && c.percent <= 100 &&
        typeof c.fiber === 'string' && c.fiber.length > 0).slice(0, 8) : [];
      const boxes = Array.isArray(next.boxes) ? next.boxes.filter(b =>
        b && [b.x0, b.y0, b.x1, b.y1].every(Number.isFinite) &&
        b.x0 >= 0 && b.y0 >= 0 && b.x1 > b.x0 && b.y1 > b.y0 &&
        b.x1 <= next.width && b.y1 <= next.height).slice(0, 24) : [];
      // Never highlight an invented/unrelated rectangle as a matched pair:
      // its coordinates must be one of the retained, valid OCR line boxes.
      const pairBoxes = Array.isArray(next.pairBoxes) ? next.pairBoxes.filter(b =>
        b && boxes.some(line => line.x0 === b.x0 && line.y0 === b.y0 &&
          line.x1 === b.x1 && line.y1 === b.y1)).slice(0, 24) : [];
      const observations = Array.isArray(next.pairObservations)
        ? next.pairObservations.slice(0, 16) : [];
      const currentGeometry = new Map();
      for (const item of observations) {
        const b = item?.box;
        const key = item?.percent + ':' + item?.fiber;
        if (!b || !cues.some(c => c.percent === item.percent &&
            c.fiber === item.fiber) ||
            !pairBoxes.some(p => p.x0 === b.x0 && p.y0 === b.y0 &&
              p.x1 === b.x1 && p.y1 === b.y1) ||
            currentGeometry.has(key) ||
            !(Number.isFinite(next.width) && next.width > 0 &&
              Number.isFinite(next.height) && next.height > 0)) {
          currentGeometry.clear(); break;
        }
        currentGeometry.set(key, {x0: b.x0 / next.width, y0: b.y0 / next.height,
          x1: b.x1 / next.width, y1: b.y1 / next.height});
      }
      // All candidates need unique, retained, real OCR-line geometry.
      const completePairs = cues.length > 0 && currentGeometry.size === cues.length;
      const hasGeometry = Number.isFinite(next.width) && next.width > 0 &&
        Number.isFinite(next.height) && next.height > 0 && boxes.length > 0;
      const bounds = hasGeometry ? {
        x: (Math.min(...boxes.map(b => b.x0)) + Math.max(...boxes.map(b => b.x1))) /
          (2 * next.width),
        y: (Math.min(...boxes.map(b => b.y0)) + Math.max(...boxes.map(b => b.y1))) /
          (2 * next.height)
      } : null;
      // Even perfectly matching OCR boxes can be from one frozen camera frame.
      // Without an independently advancing decoded/presented-frame clock,
      // candidates remain yellow but cannot accumulate temporal stability.
      const independentFrame = next.freshFrame === true;
      const nextFingerprint = independentFrame && completePairs && bounds ?
        cues.map(c => `${c.percent}:${c.fiber.toLocaleLowerCase('tr')}`)
          .sort().join('|') : '';
      const samePairGeometry = pairGeometryAgrees(pairGeometry, currentGeometry);
      moved = !!((center && bounds &&
        Math.hypot(center.x - bounds.x, center.y - bounds.y) > MAX_DRIFT) ||
        (fingerprint && nextFingerprint === fingerprint && pairGeometry &&
          !samePairGeometry));
      if (nextFingerprint && nextFingerprint === fingerprint && !moved &&
          samePairGeometry && sampledAt - lastTime <= MAX_GAP_MS) stableFrames++;
      else stableFrames = nextFingerprint ? 1 : 0;
      fingerprint = nextFingerprint;
      center = bounds;
      pairGeometry = completePairs ? currentGeometry : null;
      lastTime = sampledAt;
      observation = {cues, boxes, pairBoxes, width: next.width, height: next.height,
        textPresent: next.textPresent === true || cues.length > 0,
        freshFrame: independentFrame};
      return view(now);
    }
    return Object.freeze({observe, view, clear});
  }
  return Object.freeze({create, geometryHint});
});
