'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const ocr = require('../web/doku_live_ocr.js');
const stability = require('../web/doku_live_stability.js');
const box = (y) => ({x0: 20, y0: y, x1: 180, y1: y + 25});
const line = (text, y) => ({text, bbox: box(y)});
const data = {blocks: [{paragraphs: [{lines: [
  line('80% PAMUK', 30), line('80% PAMUK', 130)
]}]}]};
test('duplicate literal pairs retain separate physical boxes', () => {
  const result = ocr.extract(data, 300, 300, 1, 10);
  assert.equal(result.cues.length, 1);
  assert.equal(result.pairObservations.length, 2);
  assert.equal(result.pairBoxes.length, 2);
});
test('distinct repeated rows can accumulate advisory stability, never green', () => {
  const tracker = stability.create();
  for (let i = 1; i <= 3; i++) {
    const reading = ocr.extract(data, 300, 300, i, 10);
    Object.assign(reading, {freshFrame: true, roiOnly: false});
    const result = tracker.observe(reading, i * 1000);
    assert.equal(result.level, 'yellow');
    assert.equal(result.stableFrames, i);
  }
});
test('lost duplicate row resets temporal stability', () => {
  const tracker = stability.create();
  const first = ocr.extract(data, 300, 300, 1, 10);
  first.freshFrame = true;
  tracker.observe(first, 1000);
  const second = ocr.extract({blocks:[{paragraphs:[{lines:[
    line('80% PAMUK', 30)
  ]}]}]}, 300, 300, 2, 10);
  second.freshFrame = true;
  assert.equal(tracker.observe(second, 2000).stableFrames, 1);
});
test('overlapping duplicate observations fail closed', () => {
  const tracker = stability.create();
  const reading = ocr.extract(data, 300, 300, 1, 10);
  reading.freshFrame = true;
  reading.pairObservations[1].box = reading.pairObservations[0].box;
  assert.equal(tracker.observe(reading, 1000).stableFrames, 0);
});
