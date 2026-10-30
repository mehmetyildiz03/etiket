'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {create} = require('../web/doku_live_stability.js');
const box = (x = 20) => ({x0: x, y0: 40, x1: x + 200, y1: 100});
const sample = (sequence, cues = [{percent: 80, fiber: 'pamuk'}], x = 20) => {
  const bounds = box(x);
  return {sequence, cues, boxes: [bounds], pairBoxes: [bounds],
    pairObservations: cues.map(c => ({...c, box: bounds})),
    textPresent: true, width: 1000, height: 500};
};

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


test('slow live OCR cannot present an old frame as a current label', () => {
  const s = create();
  assert.equal(s.observe({...sample(1), durationMs: 900}, 1000).stableFrames, 1);
  assert.equal(s.observe({...sample(2), durationMs: 7500}, 9000).level, 'gray');
  assert.equal(s.view(9000).boxes.length, 0);
  assert.equal(s.observe({...sample(3), durationMs: 800}, 10000).stableFrames, 1);
  assert.equal(s.observe({...sample(4), durationMs: NaN}, 11000).level, 'gray');
});

test('out-of-order and duplicate OCR frames cannot replace accepted geometry', () => {
  const s = create();
  const first = s.observe(sample(10), 1000);
  const repeated = s.observe(sample(10, [{percent: 20, fiber: 'keten'}], 500), 1100);
  assert.equal(repeated.sequence, 10);
  assert.equal(repeated.cues[0].fiber, 'pamuk');
  assert.equal(repeated.boxes[0].x0, first.boxes[0].x0);
  assert.equal(s.observe(sample(9), 1200).sequence, 10);
});

test('camera geometry advice is based on real line boxes, never a green decision', () => {
  const s = create();
  const edge = s.observe({...sample(1), boxes: [box(1)]}, 1000);
  assert.equal(require('../web/doku_live_stability.js').geometryHint(edge), 'edgeText');
  const small = s.observe({...sample(2), boxes: [
    {x0: 50, y0: 50, x1: 150, y1: 56}
  ]}, 2000);
  assert.equal(require('../web/doku_live_stability.js').geometryHint(small), 'smallText');
  assert.equal(small.level, 'yellow');
  const normal = s.observe(sample(3), 3000);
  assert.equal(require('../web/doku_live_stability.js').geometryHint(normal), null);
  const stale = s.view(10000);
  assert.equal(require('../web/doku_live_stability.js').geometryHint(stale), null);
  assert.equal(stale.level, 'gray');
});

test('invalid OCR geometry cannot trigger framing advice', () => {
  const {geometryHint} = require('../web/doku_live_stability.js');
  assert.equal(geometryHint({width: 1200, height: 675,
    boxes: [{x0: -2, y0: 0, x1: 50, y1: 30}]}), null);
  assert.equal(geometryHint({width: NaN, height: 675,
    boxes: [{x0: 0, y0: 0, x1: 50, y1: 30}]}), null);
  assert.equal(geometryHint({width: 1200, height: 675, boxes: []}), null);
});

test('pair highlight is allowed only for an actual retained text-line rectangle', () => {
  const s = create();
  const text = box(20);
  const unrelated = box(450);
  const first = s.observe({...sample(1), boxes: [text],
    pairBoxes: [text, unrelated, {x0: -5, y0: 0, x1: 10, y1: 10}]}, 1000);
  assert.equal(first.pairBoxes.length, 1);
  assert.equal(first.pairBoxes[0].x0, 20);
  assert.equal(first.level, 'yellow');
  const stale = s.view(8000);
  assert.equal(stale.pairBoxes.length, 0);
  assert.equal(stale.level, 'gray');
});

test('duplicate OCR callback cannot swap a matched-line box', () => {
  const s = create();
  const first = s.observe({...sample(10), pairBoxes: [box(20)]}, 1000);
  const duplicate = s.observe({...sample(10), pairBoxes: [box(30)]}, 1100);
  assert.equal(duplicate.pairBoxes[0].x0, first.pairBoxes[0].x0);
});


test('swapped percent–fiber lines cannot gain stability from unchanged overall center', () => {
  const s = create();
  const left = box(20), right = box(500);
  const cues = [{percent: 80, fiber: 'pamuk'}, {percent: 20, fiber: 'keten'}];
  const two = (sequence, swapped = false) => ({
    sequence, cues, boxes: [left, right], pairBoxes: [left, right],
    pairObservations: [
      {...cues[0], box: swapped ? right : left},
      {...cues[1], box: swapped ? left : right}
    ], width: 1000, height: 500, textPresent: true
  });
  assert.equal(s.observe(two(1), 1000).stableFrames, 1);
  assert.equal(s.observe(two(2), 3000).stableFrames, 2);
  const swapped = s.observe(two(3, true), 5000);
  assert.equal(swapped.stableFrames, 1);
  assert.equal(swapped.moved, true);
  assert.equal(swapped.level, 'yellow');
  assert.equal(s.observe(two(4, true), 7000).stableFrames, 2);
});

test('a pair needs its own retained OCR-line box before temporal stability counts', () => {
  const s = create();
  const missing = {...sample(1), pairObservations: []};
  assert.equal(s.observe(missing, 1000).stableFrames, 0);
  const unrelated = {...sample(2),
    pairObservations: [{percent: 80, fiber: 'pamuk', box: box(450)}]};
  assert.equal(s.observe(unrelated, 2000).stableFrames, 0);
  assert.equal(s.observe(sample(3), 3000).stableFrames, 1);
});

test('duplicate or incomplete pair observations cannot look spatially stable', () => {
  const s = create();
  const p = sample(1);
  const duplicated = {...p, pairObservations: [p.pairObservations[0],
    p.pairObservations[0]]};
  assert.equal(s.observe(duplicated, 1000).stableFrames, 0);
  const second = {...sample(2), cues: [
    {percent: 80, fiber: 'pamuk'}, {percent: 20, fiber: 'keten'}]};
  assert.equal(s.observe(second, 3000).stableFrames, 0);
  assert.equal(s.view(3000).level, 'yellow');
});

test('small per-pair jitter is tolerated but scale changes reset stability', () => {
  const s = create();
  s.observe(sample(1), 1000);
  const b = {x0: 24, y0: 42, x1: 224, y1: 102};
  assert.equal(s.observe({...sample(2), boxes: [b], pairBoxes: [b],
    pairObservations: [{percent: 80, fiber: 'pamuk', box: b}]},
  3000).stableFrames, 2);
  const huge = {x0: 0, y0: 20, x1: 500, y1: 180};
  const result = s.observe({...sample(3), boxes: [huge], pairBoxes: [huge],
    pairObservations: [{percent: 80, fiber: 'pamuk', box: huge}]}, 5000);
  assert.equal(result.stableFrames, 1);
  assert.equal(result.moved, true);
});
