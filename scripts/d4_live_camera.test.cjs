'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web/doku_live_camera.js'), 'utf8');
const stability = require('../web/doku_live_stability.js');

function setup({permission = true, delayed = false, withOcr = false} = {}) {
  const buttons = [], nodes = [], docEvents = new Map(), pageEvents = new Map();
  const tracks = [{stopped: false, stop() { this.stopped = true; }}];
  const stream = {getTracks: () => tracks, getVideoTracks: () => tracks};
  let requested, requestResolve, requestReject, timer, cameraCalls = 0, ocrResult;
  const clock = {now: 1000};
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
    dokuCaptureGuidance: {evaluate: () => null},
    dokuLiveStability: stability,
    dokuLiveOcr: withOcr ? {create: onResult => {
      ocrResult = onResult;
      return {sample() {}, stop() {}};
    }} : undefined
  });
  vm.runInContext(source, context);
  return {api: context.dokuLiveCamera, context, nodes, buttons, tracks, stream,
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
  const observation = sequence => ({sequence, width: 1200, height: 675,
    boxes: [{x0: 50, y0: 70, x1: 250, y1: 120}],
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
