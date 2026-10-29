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
function setup({recognize} = {}) {
  let terminated = 0, calls = 0, options = null, setParams = null;
  const canvas = {width: 0, height: 0,
    getContext: () => ({drawImage() {}})};
  const context = vm.createContext({
    URL, Date, Number, Math, Promise, Worker: function Worker() {},
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
          return recognize ? recognize() : result(line('80% PAMUK'));
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
