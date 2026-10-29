'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('../web/doku_live_stability.js');
const box = (x = 20) => ({x0: x, y0: 40, x1: x + 200, y1: 100});
const sample = (sequence, cues = [{percent: 80, fiber: 'pamuk'}], x = 20) =>
  ({sequence, cues, boxes: [box(x)], textPresent: true, width: 1000, height: 500});

test('requires separate ordered OCR frames and stable position, never green', () => {
  const s = create();
  assert.equal(s.observe(sample(1), 1000).stableFrames, 1);
  assert.equal(s.observe(sample(1), 1100).stableFrames, 1, 'retry not a new frame');
  assert.equal(s.observe(sample(2), 3000).stableFrames, 2);
  const third = s.observe(sample(3), 5000);
  assert.equal(third.stableFrames, 3);
  assert.equal(third.level, 'yellow', 'OCR agreement does not prove full-label coverage');
  assert.equal('verified' in third, false);
});

test('different ratios, displaced label, and missing geometry reset stability', () => {
  const s = create();
  s.observe(sample(1), 1000);
  s.observe(sample(2), 3000);
  assert.equal(s.observe(sample(3, [{percent: 20, fiber: 'keten'}]), 5000).stableFrames, 1);
  const moved = s.observe(sample(4, [{percent: 20, fiber: 'keten'}], 500), 6000);
  assert.equal(moved.moved, true);
  assert.equal(moved.stableFrames, 1);
  const missing = s.observe({...sample(5), boxes: []}, 7000);
  assert.equal(missing.stableFrames, 0);
  assert.equal(missing.level, 'yellow');
});

test('stale results disappear without persisting candidates or overlay boxes', () => {
  const s = create();
  s.observe(sample(1), 1000);
  const stale = s.view(7001);
  assert.equal(stale.level, 'gray');
  assert.equal(stale.cues.length, 0);
  assert.equal(stale.boxes.length, 0);
  assert.equal(s.observe(sample(2), 8000).stableFrames, 1);
});

test('empty OCR and invalid pair cannot increase stability', () => {
  const s = create();
  s.observe(sample(1), 1000);
  const bad = s.observe({...sample(2), cues: [{percent: 120, fiber: 'pamuk'}]}, 2000);
  assert.equal(bad.stableFrames, 0);
  const empty = s.observe({sequence: 3, cues: [], boxes: [], textPresent: false,
    width: 1000, height: 500}, 3000);
  assert.equal(empty.level, 'gray');
  assert.equal(empty.stableFrames, 0);
});
