'use strict';
// D4.2 STUDY ONLY. Pixel-only candidate, not a production OCR decision.
// No fixture angles, GT strings, OCR output, network calls or image persistence.
(function attach(root) {
  function estimate(rgba, width, height) {
    if (!Number.isInteger(width) || !Number.isInteger(height) ||
        width < 1 || height < 1 || !rgba || rgba.length !== width * height * 4) {
      throw new TypeError('Expected an RGBA image with matching dimensions');
    }
    const count = width * height;
    const mask = new Uint8Array(count);
    for (let i = 0; i < count; i++) {
      const p = i * 4;
      const gray = .299 * rgba[p] + .587 * rgba[p + 1] + .114 * rgba[p + 2];
      if (rgba[p + 3] > 127 && gray < 110) mask[i] = 1;
    }
    // Connected ink components reject whole dark backgrounds and long seams.
    // The projection-only estimator is easily dominated by these pixels.
    const queue = new Int32Array(count);
    const glyphs = [];
    for (let seed = 0; seed < count; seed++) {
      if (mask[seed] !== 1) continue;
      let head = 0, tail = 1, area = 0, sx = 0, sy = 0;
      let minX = width, maxX = 0, minY = height, maxY = 0;
      queue[0] = seed;
      mask[seed] = 2;
      while (head < tail) {
        const index = queue[head++];
        const x = index % width, y = Math.floor(index / width);
        area++; sx += x; sy += y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        for (let yy = Math.max(0, y - 1); yy <= Math.min(height - 1, y + 1); yy++) {
          for (let xx = Math.max(0, x - 1); xx <= Math.min(width - 1, x + 1); xx++) {
            const neighbor = yy * width + xx;
            if (mask[neighbor] === 1) {
              mask[neighbor] = 2;
              queue[tail++] = neighbor;
            }
          }
        }
      }
      const w = maxX - minX + 1, h = maxY - minY + 1;
      if (area >= 6 && area <= 600 && w >= 2 && w <= 44 &&
          h >= 4 && h <= 38) glyphs.push({x: sx / area, y: sy / area});
    }
    // Pair glyph centroids within a text line. Wide separations reduce the
    // effect of differing glyph shapes; nearby rows (>50px) are excluded.
    const votes = [];
    for (let i = 0; i < glyphs.length; i++) {
      for (let j = i + 1; j < glyphs.length; j++) {
        const dx = glyphs[j].x - glyphs[i].x;
        const dy = glyphs[j].y - glyphs[i].y;
        const span = Math.abs(dx);
        if (span < 35 || span > 220 || Math.abs(dy) > 55) continue;
        const angle = Math.atan2(dy, dx) * 180 / Math.PI;
        const normalized = angle > 90 ? angle - 180 : angle < -90 ? angle + 180 : angle;
        if (Math.abs(normalized) > 14) continue;
        votes.push({angle: normalized, weight: Math.min(span, 150)});
      }
    }
    if (glyphs.length < 6 || votes.length < 12) {
      return {angle: 0, usable: false, components: glyphs.length, pairs: votes.length};
    }
    votes.sort((a, b) => a.angle - b.angle);
    const half = votes.reduce((sum, vote) => sum + vote.weight, 0) / 2;
    let sum = 0, median = 0;
    for (const vote of votes) {
      sum += vote.weight;
      if (sum >= half) { median = vote.angle; break; }
    }
    return {angle: Math.round(median / .75) * .75, usable: true,
      components: glyphs.length, pairs: votes.length};
  }
  const api = Object.freeze({estimate});
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.__dokuStudySkew = api;
})(globalThis);
