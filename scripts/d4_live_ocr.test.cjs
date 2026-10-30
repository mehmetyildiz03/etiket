'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/doku_live_ocr.js'), 'utf8');

const line = (text, bbox = {x0: 12, y0: 16, x1: 220, y1: 45}) =>
  ({text, bbox});
const result = (...lines) => ({data: {text: 'not exposed to camera',
  blocks: [{paragraphs: [{lines}]}]}});
function setup({recognize, clock} = {}) {
  let terminated = 0, calls = 0, options = null, setParams = null;
  const canvas = {width: 0, height: 0,
    getContext: () => ({drawImage() {}})};
  const context = vm.createContext({
    URL, Date: clock || Date, Number, Math, Promise, Worker: function Worker() {},
    isSecureContext: true,
    document: {baseURI: 'https://example.test/etiket/',
      createElement: type => {
        assert.equal(type, 'canvas');
        return {...canvas};
      }},
    Tesseract: {createWorker: async (langs, oem, opts) => {
      assert.equal(langs.join(','), 'tur,eng');
      assert.equal(oem, 1);
      options = opts;
      return {setParameters: async p => { setParams = p; },
        recognize: async (...args) => {
          calls++;
          assert.equal(args[2].blocks, true);
          assert.equal(args[2].text, true);
          return recognize ? recognize(...args) : result(line('80% PAMUK'));
        },
        terminate: async () => { terminated++; }};
    }}
  });
  vm.runInContext(source, context);
  return {api: context.dokuLiveOcr, get calls() {return calls;},
    get terminated() {return terminated;}, get options() {return options;},
    get setParams() {return setParams;}};
}
const video = {readyState: 4, videoWidth: 1920, videoHeight: 1080};

test('same-line literal fiber+percentage cues only, no invented pairs', () => {
  const s = setup();
  const data = result(line('80% PAMUK'), line('20% polyester'),
    line('100%'), line('KETEN'), line('40% wash'),
    line('Keten %60'), line('yün 120%'), line('100% 100%'));
  const out = s.api.extract(data.data, 1200, 675, 4, 90);
  assert.equal(out.cues.length, 3);
  assert.equal(out.cues[0].percent, 80);
  assert.equal(out.cues[0].fiber, 'pamuk');
  assert.equal(out.cues[1].fiber, 'polyester');
  assert.equal(out.cues[2].fiber, 'keten');
  assert.equal(out.sequence, 4);
  assert.equal(out.boxes.length, 8);
  assert.equal(out.textPresent, true);
  assert.equal('rawText' in out, false);
});

test('multi-fiber line never pairs a percentage with the neighboring fiber', () => {
  const s = setup();
  const forward = s.api.extract(result(line('80% PAMUK 20% KETEN')).data,
    1200, 675, 1, 1);
  assert.deepEqual(Array.from(forward.cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk', '20:keten']);
  const reverse = s.api.extract(result(line('PAMUK 80% KETEN 20%')).data,
    1200, 675, 2, 1);
  assert.deepEqual(Array.from(reverse.cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk', '20:keten']);
});

test('malformed three/four digit ratios never yield a truncated percentage', () => {
  const s = setup();
  const out = s.api.extract(result(line('120% PAMUK'),
    line('1000% KETEN'), line('PAMUK 120%')).data, 1200, 675, 1, 1);
  assert.equal(out.cues.length, 0);
});

test('separate line percent and fiber, blank text and invalid boxes never create cues', () => {
  const s = setup();
  const out = s.api.extract(result(line('80%'), line('PAMUK'),
    line(' ', {x0: -1, y0: 0, x1: 2, y1: 3})).data, 300, 100, 1, 1);
  assert.equal(out.cues.length, 0);
  assert.equal(out.boxes.length, 2);
  assert.equal(out.textPresent, true);
});

test('live camera OCR is bounded, local, and does not approve text', async () => {
  const s = setup();
  const seen = [], scanner = s.api.create(v => seen.push(v));
  assert.ok(scanner);
  assert.equal(await scanner.sample(video), true);
  assert.equal(s.calls, 1);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].cues[0].percent, 80);
  assert.equal(seen[0].width, 1200);
  assert.equal(seen[0].height, 675);
  assert.equal('acceptedText' in seen[0], false);
  assert.equal(s.options.workerPath, 'https://example.test/etiket/ocr/worker.min.js');
  assert.equal(s.options.langPath, 'https://example.test/etiket/ocr/lang');
  assert.equal(s.setParams.tessedit_pageseg_mode, '6');
  assert.equal(await scanner.sample(video), false, 'sample throttled');
  scanner.stop();
  assert.equal(s.terminated, 1);
  assert.equal(await scanner.sample(video), false);
});

test('in-flight OCR is not duplicated and late results cannot update closed camera', async () => {
  let release;
  const s = setup({recognize: () => new Promise(resolve => {release = resolve;})});
  const seen = [], scanner = s.api.create(v => seen.push(v));
  const first = scanner.sample(video);
  for (let i = 0; i < 8 && !release; i++) await Promise.resolve();
  assert.equal(typeof release, 'function');
  assert.equal(await scanner.sample(video), false, 'one OCR in flight');
  scanner.stop();
  release(result(line('100% KETEN')));
  await first;
  assert.equal(seen.length, 0, 'stopped camera receives no OCR text');
  assert.equal(s.terminated, 1);
});

test('OCR engine failure is safe, terminal for the session, and does not leak raw errors', async () => {
  const s = setup({recognize: () => {throw Error('private content');}});
  let errors = 0, seen = 0;
  const scanner = s.api.create(() => seen++, () => errors++);
  assert.equal(await scanner.sample(video), true);
  assert.equal(errors, 1);
  assert.equal(seen, 0);
  assert.equal(await scanner.sample(video), false);
  scanner.stop();
});

test('insecure context disables live OCR without preventing camera fallback', () => {
  const s = setup();
  assert.equal(s.api.available, true);
  // A module's availability does not authorize photo selection or uploads.
  assert.equal(s.api.extract({blocks: []}, 100, 100, 1, 0).cues.length, 0);
});

test('matched-line boxes identify real same-line pairs, not unrelated OCR lines', () => {
  const s = setup();
  const paired = {x0: 20, y0: 60, x1: 250, y1: 90};
  const other = {x0: 20, y0: 100, x1: 250, y1: 130};
  const data = result(line('80% PAMUK 20% KETEN', paired),
    line('HAND WASH ONLY', other), line('100%', other), line('POLYESTER', other));
  const out = s.api.extract(data.data, 1200, 675, 1, 80);
  assert.equal(out.cues.length, 2);
  assert.equal(out.boxes.length, 4);
  assert.equal(out.pairBoxes.length, 1, 'one matched OCR line, not one box per cue');
  assert.equal(out.pairBoxes[0].y0, paired.y0);
  assert.equal(out.pairBoxes[0].y1, paired.y1);
  assert.deepEqual(Array.from(out.pairObservations, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten']);
  assert.ok(out.pairObservations.every(p => p.box.y0 === paired.y0));
  assert.equal('verified' in out, false);
});

test('dense labels prioritize a real composition line but never an invalid box', () => {
  const s = setup();
  const lines = Array.from({length: 24}, (_, i) =>
    line('CARE ' + i, {x0: 10, y0: i * 15, x1: 150, y1: i * 15 + 12}));
  lines.push(line('80% PAMUK', {x0: 10, y0: 380, x1: 150, y1: 400}));
  lines.push(line('20% KETEN', {x0: -10, y0: 400, x1: 150, y1: 430}));
  const out = s.api.extract(result(...lines).data, 1200, 675, 1, 80);
  assert.equal(out.cues.length, 2, 'invalid geometry may still be an unverified text cue');
  assert.equal(out.boxes.length, 24, 'bounded overlay budget');
  assert.equal(out.pairBoxes.length, 1, 'retain real composition over unrelated care text');
  assert.equal(out.pairBoxes[0].y0, 380);
  assert.equal(out.pairObservations.length, 1, 'invalid second pair cannot gain stability');
  assert.equal(out.pairObservations[0].fiber, 'pamuk');
  assert.equal('verified' in out, false);
});

test('multiple composition lines after long care text retain their actual coordinates', () => {
  const s = setup();
  const lines = Array.from({length: 24}, (_, i) =>
    line('WASH INSTRUCTION ' + i,
      {x0: 10, y0: i * 14, x1: 170, y1: i * 14 + 10}));
  lines.push(line('80% PAMUK', {x0: 12, y0: 380, x1: 200, y1: 404}));
  lines.push(line('20% KETEN', {x0: 12, y0: 415, x1: 200, y1: 439}));
  const out = s.api.extract(result(...lines).data, 1200, 675, 1, 80);
  assert.equal(out.boxes.length, 24);
  assert.deepEqual(Array.from(out.pairBoxes, b => b.y0), [380, 415]);
  assert.deepEqual(Array.from(out.pairObservations, p =>
    p.percent + ':' + p.fiber + ':' + p.box.y0),
  ['80:pamuk:380', '20:keten:415']);
  assert.ok(out.pairBoxes.every(b => out.boxes.some(lineBox =>
    lineBox.x0 === b.x0 && lineBox.y0 === b.y0 &&
    lineBox.x1 === b.x1 && lineBox.y1 === b.y1)));
  assert.equal('rawText' in out, false);
});


test('web live OCR never treats repeated or unboxed pair text as stable geometry', () => {
  const s = setup();
  const same = {x0: 20, y0: 40, x1: 250, y1: 70};
  const other = {x0: 20, y0: 100, x1: 250, y1: 130};
  const repeated = s.api.extract(result(
    line('80% PAMUK', same), line('80% PAMUK', other)).data,
  1200, 675, 1, 50);
  assert.equal(repeated.cues.length, 1);
  assert.equal(repeated.pairObservations.length, 0, 'duplicate pair ambiguous');
  const invalid = s.api.extract(result(
    line('80% PAMUK', {x0: -1, y0: 0, x1: 40, y1: 30})).data,
  1200, 675, 2, 50);
  assert.equal(invalid.cues.length, 1, 'text remains an unverified candidate');
  assert.equal(invalid.pairObservations.length, 0);
  assert.equal('rawText' in repeated, false);
});


test('web live OCR recovers printed percentage and fiber split into adjacent row tokens', () => {
  const s = setup();
  const data = result(
    line('80%', {x0: 100, y0: 300, x1: 165, y1: 335}),
    line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337}),
    line('%20', {x0: 100, y0: 400, x1: 165, y1: 435}),
    line('KETEN', {x0: 185, y0: 402, x1: 300, y1: 437}));
  const out = s.api.extract(data.data, 1200, 675, 7, 120);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten']);
  assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 300, 300, 337], [100, 400, 300, 437]]);
  assert.equal(out.pairObservations.length, 2);
  assert.ok(out.pairBoxes.every(b => out.boxes.some(x =>
    x.x0 === b.x0 && x.y0 === b.y0 && x.x1 === b.x1 && x.y1 === b.y1)));
  assert.equal('acceptedText' in out, false);
  assert.equal('verified' in out, false);
});

test('split token OCR never pairs stacked, distant, competing or intervened text', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const fiber = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const cases = [
    [ratio, line('PAMUK', {x0: 100, y0: 350, x1: 220, y1: 385})],
    [ratio, line('PAMUK', {x0: 500, y0: 302, x1: 620, y1: 337})],
    [ratio, fiber, line('KETEN', {x0: 190, y0: 302, x1: 300, y1: 337})],
    [ratio, fiber, line('OTHER', {x0: 167, y0: 300, x1: 182, y1: 337})],
    [ratio, fiber, line('20%', {x0: 105, y0: 302, x1: 165, y1: 337})],
    [line('120%', ratio.bbox), fiber],
    [line('80', ratio.bbox), fiber],
    [line('80% 20%', ratio.bbox), fiber]
  ];
  for (const lines of cases) {
    const out = s.api.extract(result(...lines).data, 1200, 675, 1, 90);
    assert.equal(out.cues.length, 0, lines.map(x => x.text).join(' | '));
    assert.equal(out.pairObservations.length, 0);
  }
});

test('split tokens cannot be joined across OCR blocks or invalid coordinates', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const fiber = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const across = {blocks: [
    {paragraphs: [{lines: [ratio]}]},
    {paragraphs: [{lines: [fiber]}]}
  ]};
  assert.equal(s.api.extract(across, 1200, 675, 1, 100).cues.length, 0);
  const invalid = result(ratio,
    line('PAMUK', {x0: -1, y0: 302, x1: 300, y1: 337}));
  assert.equal(s.api.extract(invalid.data, 1200, 675, 2, 100).cues.length, 0);
});

test('dense split-pair rows displace unrelated care boxes without exceeding budget', () => {
  const s = setup();
  const lines = Array.from({length: 24}, (_, i) =>
    line('WASH ' + i, {x0: 10, y0: i * 10, x1: 80, y1: i * 10 + 8}));
  lines.push(line('80%', {x0: 100, y0: 380, x1: 165, y1: 415}));
  lines.push(line('PAMUK', {x0: 185, y0: 382, x1: 300, y1: 417}));
  const out = s.api.extract(result(...lines).data, 1200, 675, 1, 80);
  assert.equal(out.boxes.length, 24);
  assert.equal(out.pairBoxes.length, 1);
  assert.equal(out.pairBoxes[0].y0, 380);
  assert.equal(out.pairObservations.length, 1);
});


test('after two inconclusive OCR frames, a bounded native-pixel detail pass can recover a small percentage', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const sizes = [];
  const s = setup({clock: Clock, recognize: canvas => {
    sizes.push([canvas.width, canvas.height]);
    // Synthetic OCR fixture: only the larger REAL source-pixel sample exposes
    // the literal percentage. This is not a camera accuracy benchmark.
    return canvas.width > 1200
      ? result(line('80% PAMUK', {x0: 80, y0: 140, x1: 300, y1: 175}))
      : result(line('WASH CARE', {x0: 80, y0: 140, x1: 300, y1: 175}));
  }});
  const readings = [];
  const scanner = s.api.create(reading => readings.push(reading));
  for (let i = 0; i < 4; i++) {
    assert.equal(await scanner.sample(video), true);
    now += 2100;
  }
  assert.deepEqual(sizes, [[1200, 675], [1200, 675], [1600, 900],
    [1200, 675]], 'one detail pass, then normal sampling after a matched pair');
  assert.equal(readings[0].cues.length, 0);
  assert.deepEqual(Array.from(readings[2].cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk']);
  assert.equal(readings[2].pairObservations.length, 1);
  assert.equal('acceptedText' in readings[2], false);
  assert.equal('verified' in readings[2], false);
  scanner.stop();
});

test('detail fallback never upscales a low-resolution video or bypasses throttling', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const sizes = [];
  const s = setup({clock: Clock, recognize: canvas => {
    sizes.push([canvas.width, canvas.height]);
    return result(line('WASH CARE'));
  }});
  const scanner = s.api.create(() => {});
  const smallVideo = {readyState: 4, videoWidth: 800, videoHeight: 600};
  assert.equal(await scanner.sample(smallVideo), true);
  assert.equal(await scanner.sample(smallVideo), false, '2s backpressure preserved');
  now += 2100;
  assert.equal(await scanner.sample(smallVideo), true);
  now += 2100;
  assert.equal(await scanner.sample(smallVideo), true);
  assert.deepEqual(sizes, [[800, 600], [800, 600], [800, 600]]);
  scanner.stop();
});


test('frozen decoded camera frames cannot be counted as independent OCR observations', async () => {
  let now = 10000, decoded = 17;
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const seen = [];
  const scanner = s.api.create(reading => seen.push(reading));
  const stream = {...video,
    getVideoPlaybackQuality: () => ({totalVideoFrames: decoded})};
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 1);
  now += 2100;
  assert.equal(await scanner.sample(stream), false,
    'do not rescan the same decoded camera frame after the throttle expires');
  assert.equal(s.calls, 1);
  assert.equal(seen.length, 1,
    'a frozen frame must not generate a second independent stability cue');
  decoded = 18;
  assert.equal(await scanner.sample(stream), true,
    'a genuinely newer decoded frame can be sampled');
  assert.equal(s.calls, 2);
  assert.equal(seen.length, 2);
  now += 2100;
  decoded = 1; // A renegotiated camera track may reset its frame counter.
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 3, 'a counter reset must not freeze OCR indefinitely');
  scanner.stop();
});

test('unavailable decoded-frame statistics preserve safe local OCR fallback', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const scanner = s.api.create(() => {});
  const unsupported = {...video,
    getVideoPlaybackQuality: () => { throw Error('not supported'); }};
  assert.equal(await scanner.sample(unsupported), true);
  now += 2100;
  assert.equal(await scanner.sample(unsupported), true);
  assert.equal(s.calls, 2, 'older WebKit can still read local frames');
  scanner.stop();
});


test('WebKit presented-frame callback prevents repeated OCR of a stalled frame', async () => {
  let now = 10000, callback = null, nextId = 0;
  const cancelled = [];
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const readings = [];
  const scanner = s.api.create(reading => readings.push(reading));
  const stream = {...video,
    getVideoPlaybackQuality: () => { throw Error('unavailable'); },
    requestVideoFrameCallback: cb => { callback = cb; return ++nextId; },
    cancelVideoFrameCallback: id => cancelled.push(id)};
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 1);
  assert.equal(nextId, 1, 'one frame callback, not a 30fps polling loop');
  now += 2100;
  assert.equal(await scanner.sample(stream), false, 'stalled frame is not independent');
  assert.equal(readings.length, 1);
  callback(); // A newly presented frame is reported by the browser.
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 2);
  assert.equal(nextId, 2, 'arm a single callback for the next sample');
  now += 2100;
  assert.equal(await scanner.sample(stream), false);
  scanner.stop();
  assert.deepEqual(cancelled, [2], 'cancel pending callback on camera stop');
  assert.equal(await scanner.sample(stream), false);
});

test('switching camera video elements resets both independent-frame clocks', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const scanner = s.api.create(() => {});
  const first = {...video, getVideoPlaybackQuality: () => ({totalVideoFrames: 42})};
  const second = {...video, getVideoPlaybackQuality: () => ({totalVideoFrames: 42})};
  assert.equal(await scanner.sample(first), true);
  now += 2100;
  assert.equal(await scanner.sample(second), true,
    'the same counter on a new video element is a new camera session');
  assert.equal(s.calls, 2);
  scanner.stop();
});

test('broken presented-frame callback fails open to unverified OCR fallback', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const scanner = s.api.create(() => {});
  const stream = {...video,
    requestVideoFrameCallback: () => { throw Error('not supported'); }};
  assert.equal(await scanner.sample(stream), true);
  now += 2100;
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 2);
  scanner.stop();
});
