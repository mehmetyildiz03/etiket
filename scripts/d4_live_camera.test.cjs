'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/doku_live_camera.js'), 'utf8');
const stability = require('../web/doku_live_stability.js');

function setup({permission = true, delayed = false, withOcr = false,
  torch = false, torchReject = false, torchDelayed = false, focusModes = [], focusReject = false,
  focusDelayed = false, still = null,
  noImageCapture = false, withResizeObserver = false,
  stillWidth = 4032, stillHeight = 3024, stillDecodeReject = false,
  previewBlobFailures = 0} = {}) {
  const buttons = [], nodes = [], docEvents = new Map(), pageEvents = new Map();
  const resizeObservers = [];
  let resolveFocus, resolveTorch;
  const focusPending = new Promise(resolve => { resolveFocus = resolve; });
  const torchPending = new Promise(resolve => { resolveTorch = resolve; });
  const tracks = [{stopped: false, torchEnabled: false, torchCalls: [], focusCalls: [],
    stop() { this.stopped = true; this.torchEnabled = false; },
    getCapabilities() { return {torch, focusMode: focusModes}; },
    async applyConstraints(constraints) {
      if (constraints.advanced?.[0]?.focusMode) {
        this.focusCalls.push(constraints);
        if (focusDelayed) await focusPending;
        if (focusReject) throw new DOMException('unsupported', 'OverconstrainedError');
        // Constraint replacement can reset torch unless it is requested too.
        if (torch) this.torchEnabled = constraints.advanced?.[0]?.torch === true;
        return;
      }
      this.torchCalls.push(constraints);
      if (torchDelayed) await torchPending;
      if (torchReject) throw new DOMException('unsupported', 'OverconstrainedError');
      this.torchEnabled = constraints.advanced?.[0]?.torch === true;
    }
  }];
  const stream = {getTracks: () => tracks, getVideoTracks: () => tracks};
  let requested, requestResolve, requestReject, timer, cameraCalls = 0, ocrResult;
  let remainingBlobFailures = previewBlobFailures, ocrCreates = 0, ocrStops = 0;
  const ocrCallbacks = [];
  const clock = {now: 1000};
  let bitmapCloses = 0, lastDraw = null, imageOrientationOption = null;
  const pending = new Promise((resolve, reject) => { requestResolve = resolve; requestReject = reject; });
  if (!delayed) queueMicrotask(() => permission ? requestResolve(stream) :
    requestReject(new DOMException('denied', 'NotAllowedError')));
  function element(type) {
    const events = new Map();
    const el = {
      type, style: {}, children: [], attributes: {}, textContent: '', files: [],
      clientWidth: 390, clientHeight: 220,
      offsetLeft: 0, offsetTop: 0, clientLeft: 0, clientTop: 0,
      setAttribute(k, v) { this.attributes[k] = v; },
      appendChild(child) { this.children.push(child); },
      replaceChildren(...children) { this.children = children; },
      addEventListener(k, fn) { events.set(k, fn); },
      removeEventListener(k) { events.delete(k); },
      hasListener(k) { return events.has(k); },
      async emit(k) { await events.get(k)?.(); },
      remove() { const index = nodes.indexOf(this); if (index >= 0) nodes.splice(index, 1); },
      click() { return this.emit('click'); },
      play: async () => {}, pause() {},
      videoWidth: 1920, videoHeight: 1080, readyState: 4,
      getContext() { return {
        drawImage(...args) { lastDraw = args; },
        getImageData: (_x, _y, w, h) => ({data: new Uint8ClampedArray(w * h * 4).fill(240)})
      }; },
      toBlob(fn) {
        if (remainingBlobFailures > 0) { remainingBlobFailures--; fn(null); }
        else fn(new Blob(['local-image'], {type: 'image/jpeg'}));
      }
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
    ResizeObserver: withResizeObserver ? class {
      constructor(callback) { this.callback = callback; this.disconnected = false;
        resizeObservers.push(this); }
      observe(target) { this.target = target; }
      disconnect() { this.disconnected = true; }
    } : undefined,
    ImageCapture: noImageCapture ? undefined : class {
      async takePhoto() {
        if (!still) throw new Error('native still not available');
        return still;
      }
    },
    createImageBitmap: still ? async (_blob, options) => {
      imageOrientationOption = options;
      if (stillDecodeReject) throw new Error('image decoder rejected still');
      return {width: stillWidth, height: stillHeight, isStillBitmap: true,
        close() { bitmapCloses++; }};
    } : undefined,
    dokuCaptureGuidance: {evaluate: () => null},
    dokuLiveStability: stability,
    dokuLiveOcr: withOcr ? {create: onResult => {
      ocrCreates++; ocrResult = onResult; ocrCallbacks.push(onResult);
      return {sample() {}, stop() { ocrStops++; }};
    }} : undefined
  });
  vm.runInContext(source, context);
  return {api: context.dokuLiveCamera, context, nodes, buttons, tracks, stream,
    get bitmapCloses() { return bitmapCloses; },
    get lastDraw() { return lastDraw; },
    get imageOrientationOption() { return imageOrientationOption; },
    get ocrCreates() { return ocrCreates; },
    get ocrStops() { return ocrStops; },
    emitRetiredOcr(observation) { assert.ok(ocrCallbacks.length > 1); ocrCallbacks[0](observation); },
    get requested() { return requested; }, get cameraCalls() { return cameraCalls; },
    get timer() { return timer; }, docEvents, pageEvents, resizeObservers,
    requestResolve, requestReject, resolveFocus, resolveTorch,
    advance(ms) { clock.now += ms; },
    emitOcr(observation) { assert.equal(typeof ocrResult, 'function'); ocrResult(observation); },
    button(label) { const b = buttons.find(b => b.textContent.startsWith(label));
      assert.ok(b, 'Missing '+label); return b; }};
}

test('mobile web camera opens a private rear-camera preview and captures a still', async () => {
  const s = setup({still: new Blob(['native-still'], {type: 'image/jpeg'})});
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

test('Safari without ImageCapture uses the native full-resolution still from the primary capture button', async () => {
  const s = setup({noImageCapture: true, withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0];
  const input = panel.children[3].children.find(child => child.type === 'file');
  assert.ok(input);
  assert.equal(s.buttons.some(b => b.textContent === 'Fotoğrafı çek'), false,
    'do not label a low-resolution video frame as a still photo');
  await s.button('Sistem kamerasıyla çek').emit('click');
  assert.equal(s.tracks[0].stopped, true, 'native picker releases the live stream');
  assert.equal(s.timer, null);
  assert.equal(s.ocrStops, 1, 'live OCR must stop before native camera opens');
  const fullResolution = new Blob(['synthetic-native-original'], {type: 'image/jpeg'});
  input.files = [fullResolution];
  await input.emit('change');
  assert.equal(await pending, fullResolution,
    'pass the actual native still to downstream OCR without video substitution');
  assert.equal(s.lastDraw, null, 'do not use the preview canvas');
});

test('Safari system camera 48MP still is normalized from original EXIF-oriented pixels', async () => {
  const original = new Blob(['synthetic-system-48mp'], {type: 'image/jpeg'});
  const s = setup({noImageCapture: true, still: original,
    stillWidth: 8064, stillHeight: 6048});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const input = s.nodes[0].children[3].children.find(child => child.type === 'file');
  await s.button('Sistem kamerasıyla çek').emit('click');
  assert.equal(s.tracks[0].stopped, true, 'release live video before native picker');
  input.files = [original];
  await input.emit('change');
  const result = await pending;
  assert.notEqual(result, original, 'oversized native still must fit private OCR bounds');
  assert.equal(result.type, 'image/jpeg');
  assert.ok(result.size > 0 && result.size <= 20 * 1024 * 1024);
  assert.equal(s.lastDraw[0].isStillBitmap, true,
    'resample original camera still, never lower-resolution preview video');
  assert.ok(s.lastDraw[3] * s.lastDraw[4] <= 12000000);
  assert.ok(s.lastDraw[3] * s.lastDraw[4] > 1920 * 1080);
  assert.equal(s.imageOrientationOption.imageOrientation, 'from-image');
  assert.equal(s.bitmapCloses, 1, 'release oriented bitmap after conversion');
});

test('system picker preserves original 12MP photo within private OCR limits', async () => {
  const original = new Blob(['synthetic-system-12mp'], {type: 'image/jpeg'});
  const s = setup({noImageCapture: true, still: original,
    stillWidth: 4032, stillHeight: 3024});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const input = s.nodes[0].children[3].children.find(child => child.type === 'file');
  await s.button('Sistem kamerasıyla çek').emit('click');
  input.files = [original];
  await input.emit('change');
  assert.equal(await pending, original,
    'do not re-encode a supported original or replace it with video pixels');
  assert.equal(s.lastDraw, null);
  assert.equal(s.bitmapCloses, 1);
});

test('Safari native camera cancellation never returns a fake OCR photo', async () => {
  const s = setup({noImageCapture: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const input = s.nodes[0].children[3].children.find(child => child.type === 'file');
  await s.button('Sistem kamerasıyla çek').emit('click');
  await input.emit('cancel');
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
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

test('48MP still is downsampled from oriented still pixels, not a 1080p video frame', async () => {
  const original = new Blob(['synthetic-48mp'], {type: 'image/jpeg'});
  const s = setup({still: original, stillWidth: 8064, stillHeight: 6048});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  const result = await pending;
  assert.notEqual(result, original);
  assert.equal(result.type, 'image/jpeg');
  assert.ok(result.size > 0);
  assert.equal(s.lastDraw[0].isStillBitmap, true,
    'must draw from the actual camera still, not the video element');
  assert.ok(s.lastDraw[3] * s.lastDraw[4] <= 12000000);
  assert.ok(s.lastDraw[3] * s.lastDraw[4] > 1920 * 1080,
    'preserve more source detail than the video fallback');
  assert.equal(s.imageOrientationOption.imageOrientation, 'from-image');
  assert.equal(s.bitmapCloses, 1);
  assert.equal(s.tracks[0].stopped, true);
});

test('20-32MiB still is encoded to a bounded JPEG instead of silently using video', async () => {
  const s = setup({still: {type: 'image/jpeg', size: 20 * 1024 * 1024 + 1}});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  const result = await pending;
  assert.equal(result.type, 'image/jpeg');
  assert.ok(result.size <= 20 * 1024 * 1024);
  assert.equal(s.lastDraw[0].isStillBitmap, true);
  assert.equal(s.bitmapCloses, 1);
});

test('unsupported or over-32MiB still uses the safe local video fallback', async () => {
  for (const still of [
    {type: 'image/jpeg', size: 32 * 1024 * 1024 + 1},
    new Blob(['unsupported'], {type: 'image/heic'})
  ]) {
    const s = setup({still});
    const pending = s.api.open();
    await Promise.resolve(); await Promise.resolve();
    await s.button('Fotoğrafı çek').emit('click');
    assert.equal(s.lastDraw, null, 'never silently replace an unusable still');
    assert.equal(s.tracks[0].stopped, false, 'user retains system camera option');
    await s.button('Video karesini kullan').emit('click');
    const result = await pending;
    assert.equal(result.type, 'image/jpeg');
    assert.ok(result.size > 0);
    assert.equal(s.lastDraw[0].type, 'video');
    assert.equal(s.bitmapCloses, 0, 'reject unsupported payload before decode');
  }
});

test('undecodable camera still falls back rather than losing the photo session', async () => {
  const original = new Blob(['broken-still'], {type: 'image/jpeg'});
  const s = setup({still: original, stillDecodeReject: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Fotoğrafı çek').emit('click');
  assert.equal(s.lastDraw, null, 'decode failure cannot silently use preview');
  await s.button('Video karesini kullan').emit('click');
  const result = await pending;
  assert.notEqual(result, original);
  assert.equal(result.type, 'image/jpeg');
  assert.equal(s.lastDraw[0].type, 'video');
  assert.equal(s.bitmapCloses, 0);
});

test('failed native still offers system camera without touching preview pixels', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const input = s.nodes[0].children[3].children.find(child => child.type === 'file');
  await s.button('Fotoğrafı çek').emit('click');
  assert.equal(s.lastDraw, null, 'no low-resolution video is auto-selected');
  assert.match(s.nodes[0].children[2].textContent, /Sistem kamerasını kullan/);
  assert.equal(s.ocrCreates, 2, 'live OCR safely restarts after native still failure');
  await s.button('Sistem kamerası').emit('click');
  assert.equal(s.tracks[0].stopped, true);
  const original = new Blob(['high-resolution-native-photo'], {type: 'image/jpeg'});
  input.files = [original];
  await input.emit('change');
  assert.equal(await pending, original, 'use original system-camera still');
  assert.equal(s.lastDraw, null, 'never sample a video fallback on this path');
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

test('changing hardware light retires pre-light OCR boxes and stability', async () => {
  const s = setup({torch: true, withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const status = s.nodes[0].children[2];
  const overlay = s.nodes[0].children[1].children[1];
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  const observation = sequence => ({sequence, width: 1200, height: 675,
    boxes: [box], pairBoxes: [box],
    pairObservations: [{percent: 80, fiber: 'pamuk', box}],
    cues: [{percent: 80, fiber: 'pamuk'}], textPresent: true, freshFrame: true});
  s.emitOcr(observation(1));
  assert.equal(overlay.children.length, 1);
  await s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.tracks[0].torchEnabled, true);
  assert.equal(s.ocrStops, 1, 'pre-light worker is retired');
  assert.equal(s.ocrCreates, 2, 'post-light worker is fresh');
  assert.equal(overlay.children.length, 0, 'pre-light rectangles disappear');
  assert.match(status.textContent, /Gri/);
  s.emitRetiredOcr(observation(2));
  assert.equal(overlay.children.length, 0, 'retired callback cannot revive old pixels');
  s.emitOcr(observation(1));
  assert.match(status.textContent, /Tek kare adayı/);
  assert.doesNotMatch(status.textContent, /2 ayrı OCR karesinde/);
  await s.button('Kamera ışığını kapat').emit('click');
  assert.equal(s.ocrStops, 2);
  assert.equal(s.ocrCreates, 3);
  assert.equal(overlay.children.length, 0);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('pending hardware torch request cannot publish pre-toggle OCR or scan new frames', async () => {
  const s = setup({torch: true, torchDelayed: true, withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const overlay = s.nodes[0].children[1].children[1];
  const old = {sequence: 1, width: 1200, height: 675,
    boxes: [{x0: 20, y0: 20, x1: 150, y1: 50}],
    cues: [{percent: 80, fiber: 'pamuk'}], textPresent: true};
  s.emitOcr(old);
  assert.equal(overlay.children.length, 1);
  const toggling = s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.ocrStops, 1);
  assert.equal(s.ocrCreates, 1, 'no new worker until hardware request finishes');
  s.emitOcr(old); // The still-retained callback is now generation-invalid.
  assert.equal(overlay.children.length, 0);
  s.timer();
  assert.equal(s.ocrCreates, 1);
  s.resolveTorch();
  await toggling;
  assert.equal(s.ocrCreates, 2);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('rejected torch change resumes fresh OCR without trusting old lighting', async () => {
  const s = setup({torch: true, torchReject: true, withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.ocrStops, 1);
  assert.equal(s.ocrCreates, 2, 'failed constraints do not strand scanning');
  assert.equal(s.button('Kamera ışığını aç').style.display, 'none');
  assert.match(s.nodes[0].children[2].textContent, /ortam ışığını artır/);
  s.emitRetiredOcr({sequence: 1, width: 1200, height: 675,
    boxes: [{x0: 20, y0: 20, x1: 100, y1: 40}],
    cues: [{percent: 80, fiber: 'pamuk'}], textPresent: true});
  assert.match(s.nodes[0].children[2].textContent, /Gri/);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('unsupported camera torch is hidden while capture remains usable', async () => {
  const s = setup({still: new Blob(['native-still'], {type: 'image/jpeg'})});
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
    cues: [{percent: 80, fiber: 'pamuk'}], textPresent: true, freshFrame: true});
  s.emitOcr(observation(1));
  assert.match(status.textContent, /Tek kare adayı/);
  assert.equal(overlay.children.length, 1);
  s.advance(2000);
  s.emitOcr(observation(2));
  assert.match(status.textContent, /2 ayrı OCR karesinde/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.emitOcr({...observation(3), freshFrame: false});
  assert.match(status.textContent, /bağımsız yeni kamera karesi doğrulanamadı/);
  assert.doesNotMatch(status.textContent, /3 ayrı OCR karesinde/);
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
  assert.equal(overlay.children.length, 2,
    'matched pair is yellow once; unrelated text remains gray');
  assert.match(overlay.children[0].style.cssText, /dashed #c4cbd0/);
  assert.match(overlay.children[1].style.cssText, /solid #ffd45c/);
  assert.match(status.textContent, /Sarı/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.advance(7000); s.timer();
  assert.equal(overlay.children.length, 0);
  s.api.cancel();
  assert.equal(await pending, null);
});


test('web OCR boxes align to the bordered video content and reset after viewport resize', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0], video = panel.children[1].children[0];
  const overlay = panel.children[1].children[1], status = panel.children[2];
  // The video is offset within the overlay frame, with a 3px CSS border.
  video.offsetLeft = 7; video.offsetTop = 11;
  video.clientLeft = 3; video.clientTop = 3;
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  const observation = sequence => ({sequence, width: 1200, height: 675,
    textPresent: true, boxes: [box], pairBoxes: [box],
    pairObservations: [{percent: 80, fiber: 'pamuk', box}],
    cues: [{percent: 80, fiber: 'pamuk'}]});
  s.emitOcr(observation(1));
  assert.equal(overlay.children.length, 1);
  const scale = Math.min(video.clientWidth / video.videoWidth,
    video.clientHeight / video.videoHeight);
  const expectedX = 10 + (video.clientWidth - video.videoWidth * scale) / 2 +
    box.x0 / 1200 * video.videoWidth * scale;
  const expectedY = 14 + (video.clientHeight - video.videoHeight * scale) / 2 +
    box.y0 / 675 * video.videoHeight * scale;
  assert.ok(Math.abs(parseFloat(overlay.children[0].style.left) - expectedX) < .01);
  assert.ok(Math.abs(parseFloat(overlay.children[0].style.top) - expectedY) < .01);
  assert.equal(typeof s.pageEvents.get('resize'), 'function');
  s.pageEvents.get('resize')();
  assert.equal(overlay.children.length, 0, 'resize cannot retain misplaced OCR boxes');
  assert.match(status.textContent, /Gri/);
  s.emitOcr({...observation(2), durationMs: 500});
  assert.equal(overlay.children.length, 0,
    'a delayed result sampled before resize cannot revive old boxes');
  assert.match(status.textContent, /Gri/);
  s.advance(2000);
  s.emitOcr({...observation(3), durationMs: 100});
  assert.match(status.textContent, /Tek kare adayı/,
    'a new viewport requires new independent OCR evidence');
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(s.pageEvents.has('resize'), false, 'resize listener is cleaned up');
});

test('intrinsic video resize invalidates OCR boxes without a window resize', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0], video = panel.children[1].children[0];
  const overlay = panel.children[1].children[1], status = panel.children[2];
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  const obs = (sequence, durationMs) => ({
    sequence, durationMs, width: 1200, height: 675, textPresent: true,
    boxes: [box], pairBoxes: [box],
    pairObservations: [{percent: 80, fiber: 'pamuk', box}],
    cues: [{percent: 80, fiber: 'pamuk'}]
  });
  assert.equal(video.hasListener('resize'), true);
  assert.equal(video.hasListener('loadedmetadata'), true);
  s.emitOcr(obs(1, 100));
  assert.equal(overlay.children.length, 1);
  await video.emit('resize'); // Camera track renegotiated; viewport unchanged.
  assert.equal(overlay.children.length, 0);
  assert.match(status.textContent, /Gri/);
  s.emitOcr(obs(2, 500)); // Sample began before the camera size change.
  assert.equal(overlay.children.length, 0);
  s.advance(2000);
  s.emitOcr(obs(3, 100));
  assert.equal(overlay.children.length, 1);
  assert.match(status.textContent, /Tek kare adayı/);
  await video.emit('loadedmetadata');
  assert.equal(overlay.children.length, 0);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(video.hasListener('resize'), false);
  assert.equal(video.hasListener('loadedmetadata'), false);
});

test('responsive video resize observer clears stale OCR boxes and disconnects', async () => {
  const s = setup({withOcr: true, withResizeObserver: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0], video = panel.children[1].children[0];
  const overlay = panel.children[1].children[1], status = panel.children[2];
  assert.equal(s.resizeObservers.length, 1);
  assert.equal(s.resizeObservers[0].target, video);
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  s.emitOcr({sequence: 1, width: 1200, height: 675,
    textPresent: true, boxes: [box], pairBoxes: [box],
    cues: [{percent: 80, fiber: 'pamuk'}]});
  assert.equal(overlay.children.length, 1);
  s.resizeObservers[0].callback();
  assert.equal(overlay.children.length, 0);
  assert.match(status.textContent, /Gri/);
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(s.resizeObservers[0].disconnected, true);
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
    width: 675, height: 1200}).textMetrics, null,
  'rotated OCR coordinates must not sample the wrong camera pixels');
  assert.equal(s.api.sampleQuality(video, canvas, {...reading,
    pairBoxes: [{x0: -10, y0: 0, x1: 20, y1: 30}],
    boxes: [{x0: -10, y0: 0, x1: 20, y1: 30}]}).textMetrics, null,
  'invalid geometry cannot drive image-quality advice');
});


test('rotated WebKit preview rejects stale OCR boxes and restores portrait hints', async () => {
  const s = setup({withOcr: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const panel = s.nodes[0], video = panel.children[1].children[0];
  const overlay = panel.children[1].children[1], status = panel.children[2];
  const pair = {x0: 50, y0: 70, x1: 250, y1: 120};
  video.videoWidth = 1080; video.videoHeight = 1920;
  const observation = (sequence, width, height) => ({
    sequence, width, height, textPresent: true,
    boxes: [pair], pairBoxes: [pair],
    pairObservations: [{percent: 80, fiber: 'pamuk', box: pair}],
    cues: [{percent: 80, fiber: 'pamuk'}]
  });
  s.emitOcr(observation(1, 1200, 675));
  assert.equal(overlay.children.length, 0, 'landscape OCR must not paint on portrait preview');
  assert.match(status.textContent, /Gri/);
  s.advance(2000);
  s.emitOcr(observation(2, 675, 1200));
  assert.equal(overlay.children.length, 1, 'matching portrait OCR may paint advisory box');
  assert.match(status.textContent, /Tek kare adayı/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.api.cancel();
  assert.equal(await pending, null);
});


test('failed still capture restarts local OCR, discards retired results and permits retry', async () => {
  const s = setup({withOcr: true, previewBlobFailures: 1});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const status = s.nodes[0].children[2];
  const overlay = s.nodes[0].children[1].children[1];
  assert.equal(s.ocrCreates, 1);
  await s.button('Fotoğrafı çek').emit('click');
  assert.equal(s.ocrStops, 1, 'old worker stopped before capture');
  assert.equal(s.ocrCreates, 2, 'new worker starts after failed capture');
  assert.equal(s.tracks[0].stopped, false, 'camera remains available for retry');
  assert.match(status.textContent, /Yüksek çözünürlüklü fotoğraf alınamadı/);
  assert.equal(s.button('Video karesini kullan').type, 'button');
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  const observation = {sequence: 1, width: 1200, height: 675,
    textPresent: true, boxes: [box], pairBoxes: [box],
    cues: [{percent: 80, fiber: 'pamuk'}],
    pairObservations: [{percent: 80, fiber: 'pamuk', box}]};
  s.emitRetiredOcr(observation);
  assert.equal(overlay.children.length, 0, 'retired worker cannot paint stale boxes');
  assert.match(status.textContent, /Yüksek çözünürlüklü fotoğraf alınamadı/);
  s.emitOcr(observation);
  assert.match(status.textContent, /Sarı/);
  assert.equal(overlay.children.length, 1);
  await s.button('Video karesini kullan').emit('click');
  assert.equal(s.ocrCreates, 3, 'failed explicit preview capture restarts local OCR');
  assert.match(status.textContent, /Çekim başarısız/);
  await s.button('Video karesini kullan').emit('click');
  const result = await pending;
  assert.equal(result.type, 'image/jpeg');
  assert.ok(result.size > 0);
  assert.equal(s.tracks[0].stopped, true);
  assert.equal(s.nodes.length, 0);
});


test('separated OCR lines use their own pixels for light advice, not dark garment between', () => {
  const s = setup();
  const canvas = {
    width: 0, height: 0,
    getContext() {
      return {drawImage() {}, getImageData: (_x, _y, w, h) => {
        const data = new Uint8ClampedArray(w * h * 4);
        for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
          // Two bright label lines with a dark garment between them.
          const v = (x < 55 || x >= 105) && y >= 20 && y < 70 ? 245 : 8;
          const p = (y * w + x) * 4;
          data[p] = data[p + 1] = data[p + 2] = v;
          data[p + 3] = 255;
        }
        return {data};
      }};
    }
  };
  const line1 = {x0: 150, y0: 263, x1: 300, y1: 413};
  const line2 = {x0: 900, y0: 263, x1: 1050, y1: 413};
  const video = {videoWidth: 1600, videoHeight: 900, readyState: 4};
  const reading = {stale: false, width: 1200, height: 675,
    boxes: [line1, line2], pairBoxes: [line1, line2]};
  const metrics = s.api.sampleQuality(video, canvas, reading);
  assert.ok(metrics.meanLuminance < 150, 'garment makes full-frame mean misleading');
  assert.ok(metrics.textMetrics.meanLuminance >= 232,
    'both visible OCR lines are bright despite dark space between them');
  assert.ok(metrics.textMetrics.dynamicRange <= 16);
  assert.equal(require('../web/doku_capture_guidance.js').evaluate(metrics.textMetrics),
    'veryBright', 'advice must reflect measured line pixels');
  assert.equal('rawText' in metrics, false);
  assert.equal('image' in metrics, false);
  assert.equal(s.api.sampleQuality(video, canvas, {...reading, stale: true}).textMetrics,
    null, 'stale OCR coordinates cannot drive light advice');
});

test('supported browser single-shot refocus clears old OCR and restarts local scanner', async () => {
  const s = setup({withOcr: true, focusModes: ['continuous', 'single-shot']});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const overlay = s.nodes[0].children[1].children[1];
  const status = s.nodes[0].children[2];
  const box = {x0: 50, y0: 70, x1: 250, y1: 120};
  const observation = sequence => ({
    sequence, width: 1200, height: 675, textPresent: true,
    boxes: [box], pairBoxes: [box],
    cues: [{percent: 80, fiber: 'pamuk'}],
    pairObservations: [{percent: 80, fiber: 'pamuk', box}]
  });
  s.emitOcr(observation(1));
  assert.equal(overlay.children.length, 1);
  assert.equal(s.button('Yeniden odakla').style.display, '');
  await s.button('Yeniden odakla').emit('click');
  assert.equal(s.tracks[0].focusCalls.length, 1);
  assert.equal(s.tracks[0].focusCalls[0].advanced[0].focusMode, 'single-shot');
  assert.equal(s.ocrStops, 1, 'pre-focus OCR worker must stop');
  assert.equal(s.ocrCreates, 2, 'new OCR worker starts after focus request');
  assert.equal(overlay.children.length, 0, 'old coordinates must disappear');
  assert.match(status.textContent, /Yeniden odak istendi/);
  s.emitRetiredOcr(observation(2));
  assert.equal(overlay.children.length, 0, 'retired worker cannot revive stale boxes');
  s.emitOcr(observation(1));
  assert.equal(overlay.children.length, 1, 'new OCR may provide new yellow candidates');
  assert.match(status.textContent, /Sarı/);
  assert.doesNotMatch(status.textContent, /Yeşil|onaylandı/);
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].stopped, true);
});

test('Safari or unsupported browser never requests speculative camera focus', async () => {
  const s = setup({withOcr: true, focusModes: ['continuous']});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  assert.equal(s.button('Yeniden odakla').style.display, 'none');
  await s.button('Yeniden odakla').emit('click');
  assert.equal(s.tracks[0].focusCalls.length, 0);
  assert.equal(s.ocrStops, 0);
  assert.equal(s.ocrCreates, 1);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('rejected browser refocus safely falls back without stale OCR or lost capture', async () => {
  const s = setup({withOcr: true, focusModes: ['single-shot'], focusReject: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Yeniden odakla').emit('click');
  assert.equal(s.button('Yeniden odakla').style.display, 'none');
  assert.equal(s.ocrCreates, 2, 'OCR resumes after rejected focus request');
  assert.match(s.nodes[0].children[2].textContent, /yeniden odak uygulanamadı/);
  assert.equal(s.tracks[0].stopped, false);
  await s.button('Fotoğrafı çek').emit('click');
  assert.match(s.nodes[0].children[2].textContent, /Yüksek çözünürlüklü fotoğraf alınamadı/);
  s.api.cancel();
  assert.equal(await pending, null);
});

test('closing camera during pending refocus cannot restart OCR or revive UI', async () => {
  const s = setup({withOcr: true, focusModes: ['single-shot'], focusDelayed: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const focus = s.button('Yeniden odakla').emit('click');
  assert.equal(s.ocrStops, 1);
  assert.equal(s.ocrCreates, 1);
  s.api.cancel();
  assert.equal(await pending, null);
  s.resolveFocus();
  await focus;
  assert.equal(s.ocrCreates, 1, 'no new scanner after camera shutdown');
  assert.equal(s.nodes.length, 0);
  assert.equal(s.tracks[0].stopped, true);
});

test('web refocus preserves an explicitly enabled camera light', async () => {
  const s = setup({withOcr: true, torch: true, focusModes: ['single-shot']});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  await s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.tracks[0].torchEnabled, true);
  await s.button('Yeniden odakla').emit('click');
  assert.equal(s.tracks[0].focusCalls.length, 1);
  assert.equal(s.tracks[0].focusCalls[0].advanced[0].focusMode, 'single-shot');
  assert.equal(s.tracks[0].focusCalls[0].advanced[0].torch, true);
  assert.equal(s.tracks[0].torchEnabled, true,
    'requesting focus must not silently turn off an active torch');
  s.api.cancel();
  assert.equal(await pending, null);
  assert.equal(s.tracks[0].torchEnabled, false, 'camera close releases the torch');
});

test('pending browser refocus blocks conflicting torch constraints', async () => {
  const s = setup({withOcr: true, torch: true, focusModes: ['single-shot'],
    focusDelayed: true});
  const pending = s.api.open();
  await Promise.resolve(); await Promise.resolve();
  const focusing = s.button('Yeniden odakla').emit('click');
  await s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.tracks[0].torchCalls.length, 0,
    'a concurrent torch toggle must not overwrite the in-flight focus request');
  s.resolveFocus();
  await focusing;
  await s.button('Kamera ışığını aç').emit('click');
  assert.equal(s.tracks[0].torchCalls.length, 1, 'torch works again after focus');
  s.api.cancel();
  assert.equal(await pending, null);
});
