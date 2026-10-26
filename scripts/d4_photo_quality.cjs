'use strict';

// D4.2 — deterministic, local-only camera frame diagnostics.
// Pure pixel math: never sends data, never modifies the input or invents OCR text.
// RGBA input from a downsampled canvas; outputs diagnostics, not correctness claims.
function measureFrame({data, width, height}) {
  if (!Number.isInteger(width) || !Number.isInteger(height) ||
      width < 16 || height < 16 || width * height > 400000 ||
      !data || data.length !== width * height * 4) {
    throw new RangeError('Invalid or oversized frame sample');
  }
  const luminance = new Uint8Array(width * height);
  let sum = 0, min = 255, max = 0;
  for (let i = 0; i < luminance.length; i++) {
    const p = 4 * i;
    const value = Math.round(0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2]);
    luminance[i] = value;
    sum += value;
    min = Math.min(min, value); max = Math.max(max, value);
  }
  // Mean absolute 4-neighbour Laplacian; not a calibrated focus probability.
  let edges = 0, count = 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * width + x;
      edges += Math.abs(4 * luminance[i] - luminance[i-1] -
        luminance[i+1] - luminance[i-width] - luminance[i+width]);
      count++;
    }
  }
  return Object.freeze({
    meanLuminance: sum / luminance.length,
    dynamicRange: max - min,
    edgeEnergy: edges / count,
    // Metrics are for comparisons against controlled test fixtures only.
    // No global "blurry" threshold: seams, weave, shadows and font size
    // can produce high edge energy without readable label glyphs.
    sampleWidth: width,
    sampleHeight: height
  });
}

module.exports = {measureFrame};
