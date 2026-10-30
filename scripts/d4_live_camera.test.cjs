'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/doku_live_camera.js'), 'utf8');
const stability = require('../web/doku_live_stability.js');

function setup({permission = true, delayed = false, withOcr = false,
  torch = false, torchReject = false, still = null,
  stillWidth = 4032, stillHeight = 3024, stillDecodeReject = false} = {}) {
  const buttons = [], nodes = [], docEvents = new Map(), pageEvents = new Map();
  const tracks = [{stopped: false, torchEnabled: false, torchCalls: [],
    stop() { this.stopped = true; this.torchEnabled = false; },
    getCapabilities() { return {torch}; },
    async applyConstraints(constraints) {
      this.torchCalls.push(constraints);
      if (torchReject) throw new DOMException('unsupported', 'OverconstrainedError');
      this.torchEnabled = constraints.advanced?.[0]?.torch === true;
    }
  }];
  const stream = {getTracks: () => tracks, getVideoTracks: () => tracks};
  let requested, requestResolve, requestReject, timer, cameraCalls = 0, ocrResult;
  const clock = {now: 1000};
  let bitmapCloses = 0;
  const pending = new Promise((resolve, reject) => { requestResolve = resolve; requestReject = reject; });
  if (!delayed) queueMicrotask(() => permission ? requestResolve(stream) :
    requestReject(new DOMException('denied', 'NotAllowedError')));
  function element(type) {
    const events = new Map();
    const el = {
      type, style: {}, children: [], attributes: {}, textContent: '', files: [],
      clientWidth: 390, clientHeight: 220,
      setAttribute(k, v) { this.attributes[k] = v; },
      appendChild(child) { this.children.push(child); },
      replaceChildren(...children) { this.children = children; },
      addEventListener(k, fn) { events.set(k, fn); },
      async emit(k) { await events.get(k)?.(); },
      remove() { const index = nodes.indexOf(this); if (index >= 0) nodes.splice(index, 1); },
      click() { return this.emit('click'); },
      play: async () => {}, pause() {},
      videoWidth: 1920, videoHeight: 1080, readyState: 4,
      getContext() { return {
        drawImage() {},
        getImageData: (_x, _y, w, h) => ({data: new Uint8ClampedArray(w * h * 4).fill(240)})
      }; },
      toBlob(fn) { fn(new Blob(['local-image'], {type: 'image/jpeg'})); }
    };
    if (type === 'button') buttons.push(el);
    return el;
  }
  const document = {
    hidden: false, createElement: element,
    body: {appendChild(node) { nodes.push(node); }},
    addEventListener: (name, fn) => docEvents.set(name, fn),
    removeEventListener: name => docEvents.delete(name)
  };
  const context = vm.createContext({
    DOMException, Blob, Uint8Array, Uint8ClampedArray, Promise,
    Date: class extends Date { static now() { return clock.now; } },
    isSecureContext: true, document,
    navigator: {mediaDevices: {getUserMedia: constraints => {
      requested = constraints; cameraCalls++; return pending;
    }}},
    addEventListener: (name, fn) => pageEvents.set(name, fn),
    removeEventListener: name => pageEvents.delete(name),
    setInterval: fn => { timer = fn; return 1; },
    clearInterval: () => { timer = null; },
    setTimeout, clearTimeout,
    ImageCapture: still ? class { async takePhoto() { return still; } } : undefined,
    createImageBitmap: still ? async () => {
      if (stillDecodeReject) throw new Error('image decoder rejected still');
      return {width: stillWidth, height: stillHeight,
        close() { bitmapCloses++; }};
    } : undefined,
    dokuCaptureGuidance: {evaluate: () => null},
    dokuLiveStability: stability,
    dokuLiveOcr: withOcr ? {create: onResult => {
      ocrResult = onResult;
      return {sample() {}, stop() {}};
    }} : undefined
  });
  vm.runInContext(source, context);
  return {api: context.dokuLiveCamera, context, nodes, buttons, tracks, stream,
    get bitmapCloses() { return bitmapCloses; },
    get requested() { return requested; }, get cameraCalls() { return cameraCalls; },
    get timer() { return timer; }, docEvents, pageEvents, requestResolve, requestReject,
    advance(ms) { clock.now += ms; },
    emitOcr(observation) { assert.equal(typeof ocrResult, 'function'); ocrResult(observation); },
    button(label) { const b = buttons.find(b => b.textContent.startsWith(label));
      assert.ok(b, 'Missing '+label); return b; }};
}

test('mobile web camera opens a private rear-camera preview and captures a still', async () => {
  const s = setup();
  assert.equal(s.api.available, true);
  const photo = s.api.open();
  assert.equal(s.nodes.length, 1);
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(s.requested.audio, false);
  assert.equal(s.requested.video.facingMode.ideal, 'environment');
  assert.equal(s.nodes[0].attributes['aria-modal'], 'true');
  await s.button('Fotoğrafı çek').emit('click');
  const blob = await photo;
  assert.equal(blob.type, 'image/jpeg');
  assert.ok(blob.size > 0);
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.nodes.length, 0);
  assert.equal(s.timer, null);
  assert.equal(s.docEvents.size, 0);
  assert.equal(s.pageEvents.size, 0);
});

test('full-resolution still is retained when decoded pixels fit the private OCR bounds', async () => {
  const original = new Blob(['synthetic-still'], {type: 'image/jpeg'});
  const s = setup({still: original, stillWidth: 4032, stillHeight: 3024});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  assert.equal(await pending, original, 'preserve actual camera still, not 1080p preview');
  assert.equal(s.bitmapCloses, 1, 'release decoded bitmap from device memory');
  assert.equal(s.tracks[0].stopped, true);
});

test('oversized 48MP still falls back to bounded preview before the OCR handoff', async () => {
  const original = new Blob(['synthetic-48mp'], {type: 'image/jpeg'});
  const s = setup({still: original, stillWidth: 8064, stillHeight: 6048});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  const result = await pending;
  assert.notEqual(result, original);
  assert.equal(result.type, 'image/jpeg');
  assert.ok(result.size > 0);
  assert.equal(s.bitmapCloses, 1);
  assert.equal(s.tracks[0].stopped, true);
});

test('over-20MiB or unsupported camera still uses the safe local fallback', async () => {
  for (const still of [
    {type: 'image/jpeg', size: 20 * 1024 * 1024 + 1},
    new Blob(['unsupported'], {type: 'image/heic'})
  ]) {
    const s = setup({still});
    const pending = s.api.open();
    await Promise.resolve(); await Promise.resolve();
    await s.button('Fotoğrafı çek').emit('click');
    const result = await pending;
    assert.equal(result.type, 'image/jpeg');
    assert.ok(result.size > 0);
    assert.equal(s.bitmapCloses, 0, 'reject unsupported payload before decode');
  }
});

test('undecodable camera still falls back rather than losing the photo session', async () => {
  const original = new Blob(['broken-still'], {type: 'image/jpeg'});
  const s = setup({still: original, stillDecodeReject: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  const result = await pending;
  assert.notEqual(result, original);
  assert.equal(result.type, 'image/jpeg');
  assert.equal(s.bitmapCloses, 0);
});

test('optional hardware torch can be toggled without touching OCR or captured data', async () => {
  const s = setup({torch: true});
  const pending = s.api.open();
  await Promise.resolve();
  await Promise.resolve();
  const control = s.button('Kamera ışığını aç');
  assert.equal(control.style.display, '');
  assert.equal(control.attributes['aria-pressed'], 'false');
  await control.emit('click');
  assert.equal(s.tracks[0].torchEnabled, true);
  assert.equal(control.textContent, 'Kamera ışığını kapat');
  assert.equal(control.attributes['aria-pressed'], 'true');
  assert.equal(s.tracks[0].torchCalls.length, 1);
  assert.equal(s.tracks[0].torchCalls[0].advanced[0].torch, true);
  await control.emit('click');
  assert.equal(s.tracks[0].torchEnabled, false);
  assert.equal(control.attributes['aria-pressed'], 'false');
  await control.emit('click');
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.tracks[0].torchEnabled, false,
    'closing the preview releases the hardware light');
});

test('unsupported camera torch is hidden while capture remains usable', async () => {
  const s = setup();
  const pending = s.api.open();
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(s.button('Kamera ışığını aç').style.display, 'none');
  assert.equal(s.tracks[0].torchCalls.length, 0);
  await s.button('Fotoğrafı çek').emit('click');
  assert.ok((await pending).size > 0);
});

test('rejected torch constraints safely retain preview and system camera fallback', async () => {
  const s = setup({torch: true, torchReject: true});
  const pending = s.api.open();
  await Promise.resolve();
  await Promise.resolve();
  const control = s.button('Kamera ışığını aç');
  await control.emit('click');
  assert.equal(control.style.display, 'none');
  assert.equal(s.tracks[0].torchEnabled, false);
  assert.equal(s.nodes.length, 1);
  assert.match(s.nodes[0].children[2].textContent, /ortam ışığını artır/);
  await s.button('Sistem kamerası').emit('click');
  assert.equal(s.tracks[0].stopped, true);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('cancelling while camera permission is pending stops a late stream', async () => {
  const s = setup({delayed: true});
  const result = s.api.open();
  s.api.cancel();
  assert.equal(await result, null);
  s.requestResolve(s.stream);
  await Promise.resolve();
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.nodes.length, 0);
});

test('permission rejection returns a safe error and cleans overlay', async () => {
  const s = setup({permission: false});
  await assert.rejects(s.api.open(), error => error.message === 'permission');
  assert.equal(s.nodes.length, 0);
  assert.equal(s.docEvents.size, 0);
});

test('system camera fallback can supply a higher-resolution original file', async () => {
  const s = setup();
  const pending = s.api.open();
  await Promise.resolve();
  const panel = s.nodes[0];
  const input = panel.children[3].children.find(child => child.type === 'file');
  assert.ok(input);
  await s.button('Sistem kamerası').emit('click');
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.pageEvents.has('focus'), false,
    'returning from a slow native camera must not schedule premature cancellation');
  s.context.document.hidden = true;
  s.docEvents.get('visibilitychange')();
  assert.equal(s.nodes.length, 1, 'native camera must not be canceled on iOS backgrounding');
  const original = new Blob(['camera-original'], {type: 'image/jpeg'});
  input.files = [original];
  await input.emit('change');
  assert.equal(await pending, original);
  assert.equal(s.tracks[0].stopped, true);
});

test('pagehide cancels and releases camera tracks without saving frames', async () => {
  const s = setup();
  const pending = s.api.open();
  await Promise.resolve();
  s.pageEvents.get('pagehide')();
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
});

test('portrait frames are sampled at bounded size for local quality hints', () => {
  const s = setup();
  const canvas = s.context.document.createElement('canvas');
  const metrics = s.api.sampleQuality({videoWidth: 1080, videoHeight: 1920, readyState: 4}, canvas);
  assert.equal(metrics.sampleHeight, 160);
  assert.equal(metrics.sampleWidth, 90);
  assert.ok(metrics.meanLuminance >= 0);
});

test('unsupported insecure or absent camera API fails closed', async () => {
  const s = setup();
  s.context.isSecureContext = false;
  assert.equal(s.api.available, false);
  await assert.rejects(s.api.open(), error => error.message === 'unsupported');
  assert.equal(s.cameraCalls, 0);
});


test('keyboard Escape cancels the preview and closes the camera stream', async () => {
  const s = setup();
  const pending = s.api.open();
  await Promise.resolve();
  const handler = s.docEvents.get('keydown');
  assert.equal(typeof handler, 'function');
  handler({key: 'Escape'});
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.nodes.length, 0);
});

test('native picker cancellation releases the session without a fake photo', async () => {
  const s = setup();
  const pending = s.api.open();
  await Promise.resolve();
  const input = s.nodes[0].children[3].children.find(child => child.type === 'file');
  await s.button('Sistem kamerası').emit('click');
  await input.emit('cancel');
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.nodes.length, 0);
});


test('live OCR status counts independent frames, resets motion and expires stale boxes', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve();
  await Promise.resolve();
  const panel = s.nodes[0];
  const status = panel.children[2];
  const overlay = panel.children[1].children[1];
  const matched = {x0: 50, y0: 70, x1: 250, y1: 120};
  const observation = sequence => ({sequence, width: 1200, height: 675,
    boxes: [matched], pairBoxes: [matched],
    pairObservations: [{percent: 80, fiber: 'pamuk', box: matched}],
    cues: [{percent: 80, fiber: 'pamuk'}], textPresent: true});
  s.emitOcr(observation(1));
  assert.match(status.textContent, /Tek kare adayı/);
  assert.equal(overlay.children.length, 1);
  s.advance(2000);
  s.emitOcr(observation(2));
  assert.match(status.textContent, /2 ayrı OCR karesinde/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.advance(7000);
  s.timer();
  assert.match(status.textContent, /Gri/);
  assert.equal(overlay.children.length, 0, 'stale OCR boxes must disappear');
  s.api.cancel();
  assert.equal(await pending, null);
});


test('late OCR callback clears old boxes and never displays an outdated pair', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0];
  const status = panel.children[2];
  const overlay = panel.children[1].children[1];
  const obs = (sequence, durationMs) => ({sequence, durationMs,
    width: 1200, height: 675, textPresent: true,
    boxes: [{x0: 50, y0: 70, x1: 250, y1: 120}],
    cues: [{percent: 80, fiber: 'pamuk'}]});
  s.emitOcr(obs(1, 800));
  assert.equal(overlay.children.length, 1);
  s.emitOcr(obs(2, 7500));
  assert.equal(overlay.children.length, 0);
  assert.match(status.textContent, /Gri/);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('live OCR gives concrete camera-distance advice from observed text geometry', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const status = s.nodes[0].children[2];
  const reading = (sequence, box) => ({
    sequence, width: 1200, height: 675, textPresent: true,
    boxes: [box], cues: [{percent: 80, fiber: 'pamuk'}]
  });
  s.emitOcr(reading(1, {x0: 2, y0: 70, x1: 250, y1: 120}));
  assert.match(status.textContent, /kadraj kenarında; biraz uzaklaş/);
  s.advance(2000);
  s.emitOcr(reading(2, {x0: 50, y0: 70, x1: 250, y1: 78}));
  assert.match(status.textContent, /etikete yaklaş, sabitle ve odakla/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('live camera distinguishes ordinary text from exact pair lines without green', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0];
  const overlay = panel.children[1].children[1];
  const status = panel.children[2];
  const matched = {x0: 50, y0: 70, x1: 250, y1: 120};
  const other = {x0: 50, y0: 140, x1: 250, y1: 180};
  s.emitOcr({sequence: 1, width: 1200, height: 675, textPresent: true,
    boxes: [matched, other], pairBoxes: [matched],
    cues: [{percent: 80, fiber: 'pamuk'}]});
  assert.equal(overlay.children.length, 3);
  assert.match(overlay.children[0].style.cssText, /dashed #c4cbd0/);
  assert.match(overlay.children[1].style.cssText, /dashed #c4cbd0/);
  assert.match(overlay.children[2].style.cssText, /solid #ffd45c/);
  assert.match(status.textContent, /Sarı/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.advance(7000); s.timer();
  assert.equal(overlay.children.length, 0);
  s.api.cancel();
  assert.equal(await pending, null);
});


test('live quality uses observed OCR text pixels instead of dark surroundings', () => {
  const s = setup();
  const canvas = {
    width: 0, height: 0,
    getContext() {
      return {drawImage() {}, getImageData: (_x, _y, w, h) => {
        const data = new Uint8ClampedArray(w * h * 4);
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
          const v = x >= 60 && x < 100 && y >= 35 && y < 55
            ? (x % 5 === 0 ? 25 : 240) : 8;
          const p = (y * w + x) * 4;
          data[p] = data[p + 1] = data[p + 2] = v;
          data[p + 3] = 255;
        }
        return {data};
      }};
    }
  };
  const video = {videoWidth: 1600, videoHeight: 900, readyState: 4};
  const reading = {stale: false, width: 1200, height: 675,
    boxes: [{x0: 450, y0: 260, x1: 750, y1: 410}],
    pairBoxes: [{x0: 450, y0: 260, x1: 750, y1: 410}]};
  const measured = s.api.sampleQuality(video, canvas, reading);
  assert.ok(measured.meanLuminance < 30, 'dark surroundings dominate full frame');
  assert.ok(measured.textMetrics.meanLuminance > 100,
    'text-region luminance must reflect the visible label');
  assert.ok(measured.textMetrics.dynamicRange > 100);
  assert.ok(measured.textMetrics.sampleWidth >= 16);
  assert.equal('image' in measured, false);
  assert.equal('rawText' in measured, false);
  assert.equal(s.api.sampleQuality(video, canvas, {...reading, stale: true}).textMetrics,
    null, 'stale OCR geometry cannot drive image-quality advice');
  assert.equal(s.api.sampleQuality(video, canvas, {...reading,
    pairBoxes: [{x0: -10, y0: 0, x1: 20, y1: 30}],
    boxes: [{x0: -10, y0: 0, x1: 20, y1: 30}]}).textMetrics, null,
  'invalid geometry cannot drive image-quality advice');
});
