'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {measureFrame} = require('./d4_photo_quality.cjs');
function frame(width, height, pixel) {
  const data = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const i = 4 * (y * width + x), v = pixel(x, y);
    data[i] = data[i+1] = data[i+2] = v; data[i+3] = 255;
  }
  return {width, height, data};
}
test('uniform pale frame has no edge structure or dynamic range', () => {
  const result = measureFrame(frame(32, 32, () => 240));
  assert.equal(result.dynamicRange, 0);
  assert.equal(result.edgeEnergy, 0);
  assert.equal(result.meanLuminance, 240);
});
test('alternating print has more measurable local edges than a blank frame', () => {
  const flat = measureFrame(frame(32, 32, () => 120));
  const print = measureFrame(frame(32, 32, (x) => x % 2 ? 20 : 235));
  assert.ok(print.edgeEnergy > flat.edgeEnergy);
  assert.equal(print.dynamicRange, 215);
});
test('sample is bounded and cannot mutate original pixels', () => {
  assert.throws(() => measureFrame(frame(8, 32, () => 0)), RangeError);
  assert.throws(() => measureFrame({width: 1000,height: 1000,data: new Uint8Array(4000000)}), RangeError);
  const input = frame(32,32,()=>70);
  const before = input.data.slice();
  assert.ok(Object.isFrozen(measureFrame(input)));
  assert.deepEqual(input.data, before);
});
