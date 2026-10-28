'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {estimate} = require('./d4_skew_components.cjs');

function synthetic(angle, textured = false) {
  const width = 370, height = 200, data = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = (y * width + x) * 4;
      const gray = textured && y % 9 === 0 ? 165 : 244;
      data[p] = data[p + 1] = data[p + 2] = gray;
      data[p + 3] = 255;
    }
  }
  // Two independently printed lines of disconnected glyph-like strokes.
  for (const baseline of [42, 132]) {
    for (let i = 0; i < 12; i++) {
      const cx = 25 + i * 25;
      const cy = Math.round(baseline + Math.tan(angle * Math.PI / 180) * (cx - 25));
      for (let y = cy; y < cy + 10; y++) {
        for (let x = cx; x < cx + 5; x++) {
          const p = (y * width + x) * 4;
          data[p] = data[p + 1] = data[p + 2] = 35;
        }
      }
    }
  }
  return {data, width, height};
}
for (const angle of [-9, -6, 0, 9]) {
  test('component candidate estimates synthetic glyph slope ' + angle + ' degrees', () => {
    const image = synthetic(angle, true);
    const result = estimate(image.data, image.width, image.height);
    assert.equal(result.usable, true);
    assert.ok(Math.abs(result.angle - angle) <= 1.5, JSON.stringify(result));
    assert.ok(result.components >= 20);
    assert.ok(result.pairs >= 12);
  });
}
test('rejects blank image and dark unsegmented background without invented angle', () => {
  const blank = new Uint8ClampedArray(100 * 100 * 4).fill(255);
  assert.equal(estimate(blank, 100, 100).usable, false);
  const dark = new Uint8ClampedArray(100 * 100 * 4);
  for (let i = 0; i < dark.length; i += 4) dark[i + 3] = 255;
  assert.equal(estimate(dark, 100, 100).usable, false);
});
test('rejects invalid pixel buffer', () => {
  assert.throws(() => estimate(new Uint8ClampedArray(3), 2, 2), TypeError);
});
