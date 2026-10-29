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
  const MAX_DRIFT = 0.15;

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
        return {cues: [], boxes: [], textPresent: false, stableFrames: 0,
          moved: false, stale: true, level: 'gray'};
      }
      return {cues: observation.cues, boxes: observation.boxes,
        textPresent: observation.textPresent, stableFrames, moved,
        stale: false, level: observation.textPresent ? 'yellow' : 'gray'};
    }
    function observe(next, now) {
      if (!next || !Number.isSafeInteger(next.sequence) ||
          !Number.isFinite(now) || next.sequence <= lastSequence) return view(now);
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
      observation = {cues, boxes, textPresent: next.textPresent === true || cues.length > 0};
      return view(now);
    }
    return Object.freeze({observe, view, clear});
  }
  return Object.freeze({create});
});
