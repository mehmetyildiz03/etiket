/* Doku: conservative, local-only photo capture hints. No OCR decisions. */
(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.dokuCaptureGuidance = api;
})(globalThis, function () {
  'use strict';
  // Hints are intentionally restricted to nearly featureless, extremely dark
  // or extremely bright frames. No universal blur score exists for textiles.
  // This is advisory only; it must NEVER block OCR or change recognized text.
  function evaluate(metrics) {
    if (!metrics || typeof metrics !== 'object') return null;
    const {meanLuminance: mean, dynamicRange: range, edgeEnergy: edges,
      sampleWidth: width, sampleHeight: height} = metrics;
    if (![mean, range, edges, width, height].every(Number.isFinite) ||
        mean < 0 || mean > 255 || range < 0 || range > 255 || edges < 0 ||
        !Number.isInteger(width) || !Number.isInteger(height) ||
        width < 16 || height < 16 || width * height > 400000) return null;
    // Strong evidence only: an almost featureless sample cannot show clear
    // lettering, but this does not establish the cause or OCR accuracy.
    if (range <= 16 && edges <= 3 && mean <= 32) return 'veryDark';
    if (range <= 16 && edges <= 3 && mean >= 232) return 'veryBright';
    if (range <= 12 && edges <= 2) return 'lowDetail';
    return null;
  }
  return Object.freeze({evaluate});
});
