'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {evaluate} = require('../web/doku_capture_guidance.js');
const sample = (meanLuminance, dynamicRange, edgeEnergy) =>
  ({meanLuminance, dynamicRange, edgeEnergy, sampleWidth: 128, sampleHeight: 128});
test('extreme dark and bright near-blank photos receive conservative hints', () => {
  assert.equal(evaluate(sample(12, 8, 1)), 'veryDark');
  assert.equal(evaluate(sample(246, 9, 1)), 'veryBright');
  assert.equal(evaluate(sample(125, 8, 1)), 'lowDetail');
});
test('textured, contrasty, and borderline images do not trigger a hint', () => {
  assert.equal(evaluate(sample(120, 170, 50)), null);
  assert.equal(evaluate(sample(18, 25, 10)), null);
  assert.equal(evaluate(sample(242, 20, 4)), null);
  assert.equal(evaluate(sample(127, 20, 0)), null);
});
test('missing and invalid diagnostics fail open and cannot block OCR', () => {
  for (const value of [null, undefined, {}, sample(NaN, 0, 0),
    sample(100, Infinity, 0), sample(-1, 0, 0),
    {...sample(0, 0, 0), sampleWidth: 2},
    {...sample(0, 0, 0), sampleWidth: 1000, sampleHeight: 1000}]) {
    assert.equal(evaluate(value), null);
  }
});
test('does not mutate diagnostics or produce percentages or confidence', () => {
  const input = Object.freeze(sample(5, 0, 0));
  assert.equal(evaluate(input), 'veryDark');
  assert.deepEqual(Object.keys(input).sort(),
    ['dynamicRange', 'edgeEnergy', 'meanLuminance', 'sampleHeight', 'sampleWidth'].sort());
});
