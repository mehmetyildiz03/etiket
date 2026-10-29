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

  function create() {
    let lastSequence = -1, lastTime = -Infinity, fingerprint = '',
      center = null, stableFrames = 0, observation = null, moved = false;
    function clear() {
      lastSequence = -1; lastTime = -Infinity; fingerprint = '';
      center = null; stableFrames = 0; observation = null; moved = false;
    }
    function view(now) {
      if (!Number.isFinite(now) || now - lastTime > STALE_MS || now < lastTime) {
        clear();
        return {cues: [], boxes: [], pairBoxes: [], textPresent: false, stableFrames: 0,
          moved: false, stale: true, level: 'gray', sequence: -1};
      }
      return {cues: observation.cues, boxes: observation.boxes,
        pairBoxes: observation.pairBoxes,
        width: observation.width, height: observation.height, sequence: lastSequence,
        textPresent: observation.textPresent, stableFrames, moved,
        stale: false, level: observation.textPresent ? 'yellow' : 'gray'};
    }
    function observe(next, now) {
      if (!next || !Number.isSafeInteger(next.sequence) ||
          !Number.isFinite(now) || next.sequence <= lastSequence) return view(now);
      if (next.durationMs !== undefined &&
          (!Number.isFinite(next.durationMs) || next.durationMs < 0 ||
           next.durationMs > MAX_OCR_LATENCY_MS)) {
        clear(); // Never keep stale candidates or their boxes on screen.
        return view(now);
      }
      if (now < lastTime || now - lastTime > MAX_GAP_MS) {
        fingerprint = ''; center = null; stableFrames = 0;
      }
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
      const hasGeometry = Number.isFinite(next.width) && next.width > 0 &&
        Number.isFinite(next.height) && next.height > 0 && boxes.length > 0;
      const bounds = hasGeometry ? {
        x: (Math.min(...boxes.map(b => b.x0)) + Math.max(...boxes.map(b => b.x1))) /
          (2 * next.width),
        y: (Math.min(...boxes.map(b => b.y0)) + Math.max(...boxes.map(b => b.y1))) /
          (2 * next.height)
      } : null;
      const nextFingerprint = cues.length && bounds ?
        cues.map(c => `${c.percent}:${c.fiber.toLocaleLowerCase('tr')}`)
          .sort().join('|') : '';
      moved = !!(center && bounds &&
        Math.hypot(center.x - bounds.x, center.y - bounds.y) > MAX_DRIFT);
      if (nextFingerprint && nextFingerprint === fingerprint && !moved &&
          now - lastTime <= MAX_GAP_MS) stableFrames++;
      else stableFrames = nextFingerprint ? 1 : 0;
      fingerprint = nextFingerprint;
      center = bounds;
      lastTime = now;
      observation = {cues, boxes, pairBoxes, width: next.width, height: next.height,
        textPresent: next.textPresent === true || cues.length > 0};
      return view(now);
    }
    return Object.freeze({observe, view, clear});
  }
  return Object.freeze({create, geometryHint});
});
