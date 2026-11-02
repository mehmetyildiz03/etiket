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

test('mixed printed ratio–fiber order keeps both literal live pairs without cross-pairing', () => {
  const s = setup();
  const mixed = [
    ['80% PAMUK KETEN 20%', ['80:pamuk', '20:keten']],
    ['PAMUK 80% 20% KETEN', ['80:pamuk', '20:keten']],
    ['80% PAMUK KETEN 20% 10% POLYESTER',
      ['80:pamuk', '20:keten', '10:polyester']],
    // A tempting reverse match "PAMUK 20%" overlaps the real first
    // "80% PAMUK"; it must not create a second percentage for that fiber.
    ['80% PAMUK 20% KETEN', ['80:pamuk', '20:keten']]
  ];
  for (const [printed, expected] of mixed) {
    const out = s.api.extract(result(line(printed)).data, 1200, 675, 1, 50);
    assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
      expected, printed);
    assert.equal(out.pairBoxes.length, 1, 'one real OCR line box, not invented geometry');
    assert.equal(out.pairObservations.length, expected.length);
    assert.equal('verified' in out, false, 'mixed order remains an unverified hint');
    assert.equal('acceptedText' in out, false);
  }
});

test('ambiguous live OCR percentage ownership fails closed without a tracked pair', () => {
  const s = setup();
  for (const printed of [
    'PAMUK 80% KETEN',
    'KETEN 40% PAMUK',
    '80% PAMUK 20%'
  ]) {
    const out = s.api.extract(result(line(printed)).data, 1200, 675, 1, 50);
    assert.equal(out.cues.length, 0, printed);
    assert.equal(out.pairBoxes.length, 0, printed);
    assert.equal(out.pairObservations.length, 0, printed);
    assert.equal(out.textPresent, true, 'ambiguous OCR text is still visible');
    assert.equal('acceptedText' in out, false);
    assert.equal('verified' in out, false);
  }
  const unique = s.api.extract(result(line('PAMUK 80% KETEN 20%')).data,
    1200, 675, 2, 50);
  assert.deepEqual(Array.from(unique.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten'], 'unique two-pair assignment must survive');
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
  assert.equal(seen[0].freshFrame, false, 'first OCR has no independent-frame baseline');
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

test('web live OCR recovers literal percent and fiber columns in separate Tesseract blocks', () => {
  const s = setup();
  const across = {blocks: [
    {paragraphs: [{lines: [
      line('80%', {x0: 100, y0: 300, x1: 165, y1: 335}),
      line('20%', {x0: 100, y0: 400, x1: 165, y1: 435})
    ]}]},
    {paragraphs: [{lines: [
      line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337}),
      line('KETEN', {x0: 185, y0: 402, x1: 300, y1: 437})
    ]}]}
  ]};
  const out = s.api.extract(across, 1200, 675, 1, 100);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten']);
  assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 300, 300, 337], [100, 400, 300, 437]]);
  assert.equal(out.pairObservations.length, 2);
  assert.ok(out.pairBoxes.every(b => out.boxes.some(x =>
    x.x0 === b.x0 && x.y0 === b.y0 && x.x1 === b.x1 && x.y1 === b.y1)));
  assert.equal('verified' in out, false);
  assert.equal('acceptedText' in out, false);
  assert.equal('rawText' in out, false);
});

test('cross-block OCR rejects ambiguous, intervening, missing-percent and unboxed tokens', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const fiber = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const blocks = (...groups) => ({blocks: groups.map(lines =>
    ({paragraphs: [{lines}]}))});
  const cases = [
    blocks([ratio], [fiber, line('KETEN', {x0: 185, y0: 302, x1: 300, y1: 337})]),
    blocks([ratio], [fiber], [line('OTHER', {x0: 168, y0: 302, x1: 181, y1: 336})]),
    blocks([line('80', ratio.bbox)], [fiber]),
    blocks([ratio], [line('PAMUK', {x0: 185, y0: 355, x1: 300, y1: 390})]),
    blocks([ratio], [line('PAMUK', {x0: -1, y0: 302, x1: 300, y1: 337})]),
    blocks([ratio], [fiber], [line('20%', null)])
  ];
  for (const data of cases) {
    const out = s.api.extract(data, 1200, 675, 1, 100);
    assert.equal(out.cues.length, 0, 'unsafe cross-block candidate rejected');
    assert.equal(out.pairObservations.length, 0);
  }
});

test('cross-block OCR cannot bypass bounded global ambiguity inspection', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const fiber = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const care = Array.from({length: 255}, (_, i) =>
    line('CARE ' + i, {x0: 1, y0: i, x1: 70, y1: i + 1}));
  const out = s.api.extract({blocks: [
    {paragraphs: [{lines: [ratio, ...care]}]},
    {paragraphs: [{lines: [fiber]}]}
  ]}, 1200, 675, 1, 100);
  assert.equal(out.cues.length, 0, '257 lines require fail-closed matching');
  assert.equal(out.pairObservations.length, 0);
});

test('unboxed unrelated care text does not hide adjacent real composition tokens', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const fiber = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const invalid = {x0: -2, y0: 10, x1: 120, y1: 40};
  for (const badBox of [invalid, null,
    {x0: -2, y0: 300, x1: 182, y1: 340}]) {
    const out = s.api.extract(result(ratio, fiber,
      line('WASH AT 30 C', badBox)).data, 1200, 675, 1, 100);
    assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
      ['80:pamuk']);
    assert.equal(out.pairObservations.length, 1);
    assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
      [[100, 300, 300, 337]]);
    assert.equal('acceptedText' in out, false);
  }
  for (const uncertain of ['20%', 'KETEN', '80% KETEN']) {
    const blocked = s.api.extract(result(ratio, fiber,
      line(uncertain, invalid)).data, 1200, 675, 2, 100);
    assert.equal(blocked.pairObservations.length, 0,
      'unboxed competing composition token must block spatial inference');
    assert.equal(blocked.cues.some(p => p.percent === 80 && p.fiber === 'pamuk'),
      false, 'cannot infer a pair from ambiguous geometry');
  }
});

test('dense OCR blocks keep late split percentage and fiber boxes within budget', () => {
  const s = setup();
  const lines = Array.from({length: 75}, (_, i) =>
    line('CARE INSTRUCTION ' + i,
      {x0: 10, y0: i * 5, x1: 140, y1: i * 5 + 4}));
  lines.push(line('80%', {x0: 100, y0: 480, x1: 165, y1: 515}));
  lines.push(line('PAMUK', {x0: 185, y0: 482, x1: 300, y1: 517}));
  const paragraphs = [];
  for (let i = 0; i < lines.length; i += 25) {
    paragraphs.push({lines: lines.slice(i, i + 25)});
  }
  const out = s.api.extract({blocks: [{paragraphs}]}, 1200, 675, 1, 120);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk']);
  assert.equal(out.boxes.length, 24);
  assert.equal(out.pairBoxes.length, 1);
  assert.equal(out.pairObservations.length, 1);
  assert.equal(out.pairBoxes[0].y0, 480);
  assert.equal('rawText' in out, false);
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



test('dense web OCR retains a literal split percentage and fiber after 75 care lines', () => {
  const s = setup();
  const care = Array.from({length: 75}, (_, i) =>
    line('WASH ' + i, {x0: 10, y0: i * 4, x1: 80, y1: i * 4 + 3}));
  care.push(line('80%', {x0: 100, y0: 420, x1: 165, y1: 452}));
  care.push(line('PAMUK', {x0: 185, y0: 421, x1: 300, y1: 453}));
  const out = s.api.extract(result(...care).data, 1200, 675, 1, 80);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk']);
  assert.equal(out.boxes.length, 24, 'live overlay budget remains bounded');
  assert.equal(out.pairBoxes.length, 1);
  assert.equal(out.pairObservations.length, 1);
  assert.equal(out.pairBoxes[0].y0, 420);
  assert.equal('rawText' in out, false);
  assert.equal('verified' in out, false);
});

test('dense web OCR reads composition after 30 paragraphs without approving it', () => {
  const s = setup();
  const paragraphs = Array.from({length: 45}, (_, i) => ({lines: [
    line('CARE ' + i, {x0: 10, y0: i * 5, x1: 80, y1: i * 5 + 4})
  ]}));
  paragraphs.push({lines: [
    line('20% KETEN', {x0: 100, y0: 400, x1: 310, y1: 440})
  ]});
  const out = s.api.extract({blocks: [{paragraphs}]}, 1200, 675, 2, 90);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['20:keten']);
  assert.equal(out.pairObservations.length, 1);
  assert.equal(out.pairBoxes[0].y0, 400);
  assert.equal('acceptedText' in out, false);
});

test('web live OCR bounds pathological dense blocks to 256 lines', () => {
  const s = setup();
  const care = Array.from({length: 256}, (_, i) =>
    line('CARE ' + i, {x0: 10, y0: i * 2, x1: 80, y1: i * 2 + 1}));
  care.push(line('80% PAMUK', {x0: 100, y0: 550, x1: 310, y1: 580}));
  const out = s.api.extract(result(...care).data, 1200, 675, 3, 90);
  assert.equal(out.cues.length, 0, 'no unbounded late-line processing');
  assert.ok(out.boxes.length <= 24);
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
  assert.equal(seen[0].freshFrame, false, 'first counter observation is not a second frame');
  assert.equal(seen[1].freshFrame, true, 'increased decoded counter proves new frame');
  now += 2100;
  decoded = 1; // A renegotiated camera track may reset its frame counter.
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 3, 'a counter reset must not freeze OCR indefinitely');
  assert.equal(seen[2].freshFrame, false, 'counter reset is not proof of a new frame');
  scanner.stop();
});

test('unavailable decoded-frame statistics preserve safe local OCR fallback', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const s = setup({clock: Clock});
  const seen = [];
  const scanner = s.api.create(reading => seen.push(reading));
  const unsupported = {...video,
    getVideoPlaybackQuality: () => { throw Error('not supported'); }};
  assert.equal(await scanner.sample(unsupported), true);
  now += 2100;
  assert.equal(await scanner.sample(unsupported), true);
  assert.equal(s.calls, 2, 'older WebKit can still read local frames');
  assert.ok(seen.every(reading => reading.freshFrame === false),
    'unverified frames cannot be described as independent');
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
  assert.equal(readings[0].freshFrame, false);
  callback(); // A newly presented frame is reported by the browser.
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 2);
  assert.equal(readings[1].freshFrame, true,
    'presented-frame callback proves a distinct frame');
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
  const seen = [];
  const scanner = s.api.create(reading => seen.push(reading));
  const stream = {...video,
    requestVideoFrameCallback: () => { throw Error('not supported'); }};
  assert.equal(await scanner.sample(stream), true);
  now += 2100;
  assert.equal(await scanner.sample(stream), true);
  assert.equal(s.calls, 2);
  assert.ok(seen.every(reading => reading.freshFrame === false));
  scanner.stop();
});


test('partial composition triggers native-pixel retry without inventing a missing percent', async () => {
  let now = 10000;
  const Clock = class extends Date { static now() { return now; } };
  const sizes = [];
  const s = setup({clock: Clock, recognize: canvas => {
    sizes.push([canvas.width, canvas.height]);
    const cotton = line('80% PAMUK', {x0: 60, y0: 140, x1: 290, y1: 172});
    const linen = line(canvas.width > 1200 ? '20% KETEN' : '20 KETEN',
      {x0: 60, y0: 210, x1: 290, y1: 240});
    return result(cotton, linen);
  }});
  const readings = [], scanner = s.api.create(r => readings.push(r));
  for (let i = 0; i < 4; i++) {
    assert.equal(await scanner.sample(video), true);
    now += 2100;
  }
  assert.deepEqual(sizes, [[1200, 675], [1200, 675], [1600, 900],
    [1200, 675]]);
  assert.deepEqual(Array.from(readings[0].cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk'], '20 without a printed % must not become a candidate');
  assert.equal(readings[0].detailNeeded, true);
  assert.deepEqual(Array.from(readings[2].cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk', '20:keten']);
  assert.equal(readings[2].detailNeeded, false);
  assert.equal('acceptedText' in readings[2], false);
  assert.equal('verified' in readings[2], false);
  scanner.stop();
});

test('tiny matched text requests bounded detail without green or auto-approval', () => {
  const s = setup();
  const small = s.api.extract(result(line('80% PAMUK',
    {x0: 60, y0: 100, x1: 200, y1: 110})).data, 1200, 675, 1, 80);
  assert.equal(small.cues.length, 1);
  assert.equal(small.detailNeeded, true);
  const readable = s.api.extract(result(line('80% PAMUK',
    {x0: 60, y0: 100, x1: 200, y1: 135})).data, 1200, 675, 2, 80);
  assert.equal(readable.detailNeeded, false);
  const missing = s.api.extract(result(line('20 KETEN')).data, 1200, 675, 3, 80);
  assert.equal(missing.cues.length, 0);
  assert.equal(missing.detailNeeded, true);
  for (const reading of [small, readable, missing]) {
    assert.equal('verified' in reading, false);
    assert.equal('acceptedText' in reading, false);
    assert.equal('rawText' in reading, false);
  }
});

test('web live OCR recovers an independently printed percent glyph split from its number', () => {
  const s = setup();
  const data = {blocks: [
    {paragraphs: [{lines: [
      line('80', {x0: 100, y0: 300, x1: 144, y1: 335}),
      line('%', {x0: 147, y0: 305, x1: 158, y1: 333})
    ]}]},
    {paragraphs: [{lines: [
      line('PAMUK', {x0: 180, y0: 302, x1: 300, y1: 337}),
      line('20%', {x0: 100, y0: 400, x1: 165, y1: 435}),
      line('KETEN', {x0: 185, y0: 402, x1: 300, y1: 437})
    ]}]}
  ]};
  const out = s.api.extract(data, 1200, 675, 1, 100);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['20:keten', '80:pamuk']);
  assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 400, 300, 437], [100, 300, 300, 337]]);
  assert.equal(out.pairObservations.length, 2);
  assert.equal(out.detailNeeded, false);
  assert.equal('verified' in out, false);
  assert.equal('acceptedText' in out, false);
  assert.equal('rawText' in out, false);
});

test('split percent glyph cannot invent a percentage from a bare number', () => {
  const s = setup();
  const number = line('80', {x0: 100, y0: 300, x1: 144, y1: 335});
  const fiber = line('PAMUK', {x0: 180, y0: 302, x1: 300, y1: 337});
  for (const extra of [[],
    [line('%', {x0: 180, y0: 350, x1: 192, y1: 380})],
    [line('%', {x0: 180, y0: 305, x1: 192, y1: 333})],
    [line('%', {x0: -2, y0: 305, x1: 12, y1: 333})]]) {
    const out = s.api.extract(result(number, ...extra, fiber).data,
      1200, 675, 1, 90);
    assert.equal(out.cues.length, 0);
    assert.equal(out.pairObservations.length, 0);
  }
});

test('split percent glyph fails closed on competing numbers or glyphs', () => {
  const s = setup();
  const number = line('80', {x0: 100, y0: 300, x1: 144, y1: 335});
  const mark = line('%', {x0: 147, y0: 305, x1: 158, y1: 333});
  const fiber = line('PAMUK', {x0: 180, y0: 302, x1: 300, y1: 337});
  const cases = [
    [number, mark, line('%', {x0: 148, y0: 305, x1: 159, y1: 333}), fiber],
    [number, line('20', {x0: 101, y0: 300, x1: 145, y1: 335}), mark, fiber],
    [number, mark, fiber, line('KETEN', {x0: 181, y0: 302, x1: 301, y1: 337})],
    [number, mark, line('OTHER', {x0: 160, y0: 303, x1: 176, y1: 333}), fiber]
  ];
  for (const lines of cases) {
    const out = s.api.extract(result(...lines).data, 1200, 675, 1, 90);
    assert.equal(out.cues.length, 0, lines.map(x => x.text).join(' | '));
    assert.equal(out.pairObservations.length, 0);
    assert.equal('verified' in out, false);
  }
});

test('two independently printed split glyph rows keep exact geometry', () => {
  const s = setup();
  const data = result(
    line('80', {x0: 100, y0: 300, x1: 144, y1: 335}),
    line('%', {x0: 147, y0: 305, x1: 158, y1: 333}),
    line('PAMUK', {x0: 180, y0: 302, x1: 300, y1: 337}),
    line('20', {x0: 100, y0: 400, x1: 144, y1: 435}),
    line('%', {x0: 147, y0: 405, x1: 158, y1: 433}),
    line('KETEN', {x0: 180, y0: 402, x1: 300, y1: 437}));
  const out = s.api.extract(data.data, 1200, 675, 2, 90);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten']);
  assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 300, 300, 337], [100, 400, 300, 437]]);
  assert.equal(out.pairObservations.length, 2);
  assert.equal(out.textPresent, true);
});

test('within-block spatial match is rejected when another block has a competing fiber', () => {
  const s = setup();
  const ratio = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const pamuk = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const keten = line('KETEN', {x0: 186, y0: 302, x1: 301, y1: 337});
  const data = {blocks: [
    {paragraphs: [{lines: [ratio, pamuk]}]},
    {paragraphs: [{lines: [keten]}]}
  ]};
  const out = s.api.extract(data, 1200, 675, 1, 100);
  assert.deepEqual(Array.from(out.cues), [],
    'a competing fiber in a different OCR block invalidates the earlier pair');
  assert.equal(out.pairObservations.length, 0);
  assert.equal(out.pairBoxes.length, 0);
  assert.equal(out.textPresent, true);
  assert.equal('verified' in out, false);
});

test('within-block spatial match is rejected when another block has a competing ratio', () => {
  const s = setup();
  const first = line('80%', {x0: 100, y0: 300, x1: 165, y1: 335});
  const second = line('20%', {x0: 101, y0: 300, x1: 166, y1: 335});
  const pamuk = line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337});
  const out = s.api.extract({blocks: [
    {paragraphs: [{lines: [first, pamuk]}]},
    {paragraphs: [{lines: [second]}]}
  ]}, 1200, 675, 2, 100);
  assert.equal(out.cues.length, 0, 'one fiber cannot own two plausible percentages');
  assert.equal(out.pairObservations.length, 0);
  assert.equal(out.pairBoxes.length, 0);
});

test('globally unambiguous mixed-block pairs still retain real OCR geometry', () => {
  const s = setup();
  const data = {blocks: [
    {paragraphs: [{lines: [
      line('80%', {x0: 100, y0: 300, x1: 165, y1: 335}),
      line('PAMUK', {x0: 185, y0: 302, x1: 300, y1: 337})
    ]}]},
    {paragraphs: [{lines: [
      line('20%', {x0: 100, y0: 400, x1: 165, y1: 435})
    ]}]},
    {paragraphs: [{lines: [
      line('KETEN', {x0: 185, y0: 402, x1: 300, y1: 437})
    ]}]}
  ]};
  const out = s.api.extract(data, 1200, 675, 3, 100);
  assert.deepEqual(Array.from(out.cues, p => p.percent + ':' + p.fiber),
    ['80:pamuk', '20:keten']);
  assert.deepEqual(Array.from(out.pairBoxes, b => [b.x0, b.y0, b.x1, b.y1]),
    [[100, 300, 300, 337], [100, 400, 300, 437]]);
  assert.equal(out.pairObservations.length, 2);
  assert.equal('acceptedText' in out, false);
});


test('web inline pair is rejected when another OCR block has a same-row rival', () => {
  const s = setup();
  const first = line('80% PAMUK', {x0: 100, y0: 300, x1: 320, y1: 335});
  for (const rival of ['KETEN', 'WASH KETEN', '20%', '20', '%']) {
    const data = {blocks: [
      {paragraphs: [{lines: [first]}]},
      {paragraphs: [{lines: [line(rival,
        {x0: 325, y0: 302, x1: 430, y1: 337})]}]}
    ]};
    const out = s.api.extract(data, 1200, 675, 1, 100);
    assert.equal(out.cues.length, 0, rival);
    assert.equal(out.pairObservations.length, 0, rival);
    assert.equal(out.pairBoxes.length, 0, rival);
    assert.equal(out.detailNeeded, true,
      'ambiguous printed tokens request a bounded source-pixel retry');
    assert.equal(out.textPresent, true);
    assert.equal('acceptedText' in out, false);
  }
});

test('web inline conflict check preserves independent printed rows and pairs', () => {
  const s = setup();
  const first = line('80% PAMUK', {x0: 100, y0: 300, x1: 320, y1: 335});
  const blocks = (...groups) => ({blocks: groups.map(lines =>
    ({paragraphs: [{lines}]}))});
  const differentRow = s.api.extract(blocks([first], [
    line('KETEN', {x0: 325, y0: 410, x1: 430, y1: 445})
  ]), 1200, 675, 1, 100);
  assert.deepEqual(Array.from(differentRow.cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk']);
  const twoPairs = s.api.extract(blocks([first], [
    line('20% KETEN', {x0: 400, y0: 302, x1: 640, y1: 337})
  ]), 1200, 675, 2, 100);
  assert.deepEqual(Array.from(twoPairs.cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk', '20:keten']);
  assert.equal(twoPairs.pairObservations.length, 2);
  assert.equal(twoPairs.detailNeeded, false);
});

test('web inline conflict with unlocated rival fails closed, not unrelated care', () => {
  const s = setup();
  const first = line('80% PAMUK', {x0: 100, y0: 300, x1: 320, y1: 335});
  const blocks = (...groups) => ({blocks: groups.map(lines =>
    ({paragraphs: [{lines}]}))});
  const unsafe = s.api.extract(blocks([first], [line('KETEN', null)]),
    1200, 675, 1, 100);
  assert.equal(unsafe.cues.length, 0);
  assert.equal(unsafe.pairObservations.length, 0);
  assert.equal(unsafe.detailNeeded, true);
  const safe = s.api.extract(blocks([first], [line('WASH CARE', null)]),
    1200, 675, 2, 100);
  assert.deepEqual(Array.from(safe.cues, c => c.percent + ':' + c.fiber),
    ['80:pamuk']);
});

test('web inline pairs cannot skip 257-line cross-block ambiguity inspection', () => {
  const s = setup();
  const care = Array.from({length: 256}, (_, i) =>
    line('CARE ' + i, {x0: 1, y0: i * 2, x1: 80, y1: i * 2 + 1}));
  const data = {blocks: [
    {paragraphs: [{lines: care}]},
    {paragraphs: [{lines: [
      line('80% PAMUK', {x0: 100, y0: 550, x1: 310, y1: 580})
    ]}]}
  ]};
  const out = s.api.extract(data, 1200, 675, 1, 100);
  assert.equal(out.cues.length, 0);
  assert.equal(out.pairObservations.length, 0);
  assert.equal(out.detailNeeded, true);
});
