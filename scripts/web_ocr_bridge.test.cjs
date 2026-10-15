'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const bridgeSource = fs.readFileSync(require('node:path').join(__dirname, '../web/doku_ocr.js'), 'utf8');
function png(width = 800, height = 600) {
  const bytes = new Uint8Array(32), view = new DataView(bytes.buffer);
  view.setUint32(0, 0x89504e47); view.setUint32(4, 0x0d0a1a0a);
  view.setUint32(16, width); view.setUint32(20, height);
  return new File([bytes], 'label.png', {type: 'image/png'});
}
function setup({mobile = false, secure = true, supported = true} = {}) {
  const nodes = [], revoked = [], blobs = new Map(), workers = [], listeners = {}, optionsHistory = [];
  let options, initialized = 0, decoded = 0, creation, confidence = 93, recognizedBlob, result = 'Dış kumaş\n70% Pamuk\n30% Polyester';
  const canvases = [], imageSources = [];
  class Input {
    events = {}; files = [];
    setAttribute(key, value) { this[key] = value; }
    style = {};
    addEventListener(key, fn) { this.events[key] = fn; }
    click() { if (this.denied) throw new DOMException('denied', 'NotAllowedError'); }
    remove() { nodes.splice(nodes.indexOf(this), 1); }
    async emit(key) { await this.events[key]?.(); }
  }
  class FakeWorker { constructor(url) { this.url = url; workers.push(this); } terminate() { this.stopped = true; } }
  const context = vm.createContext({
    DOMException, Blob, File, FileReader: class {}, URL: class extends URL {
      static createObjectURL(blob) { const path = `blob:${blobs.size}-${revoked.length}`; blobs.set(path, blob); return path; }
      static revokeObjectURL(path) { revoked.push(path); blobs.delete(path); }
    },
    WebAssembly: supported ? WebAssembly : undefined, Worker: FakeWorker,
    Uint8Array, DataView, setTimeout, clearTimeout,
    isSecureContext: secure, navigator: {userAgent: mobile ? 'Android test browser' : 'Desktop Chromium'},
    addEventListener: (key, fn) => { listeners[key] = fn; },
    removeEventListener: key => { delete listeners[key]; },
    Image: class {
      naturalWidth = 800; naturalHeight = 600;
      async decode() {
        decoded++;
        const blob = blobs.get(this.src); imageSources.push(blob);
        const bytes = new Uint8Array(await blob.arrayBuffer());
        if (bytes.length >= 24 && new DataView(bytes.buffer).getUint32(0) === 0x89504e47) {
          this.naturalWidth = new DataView(bytes.buffer).getUint32(16);
          this.naturalHeight = new DataView(bytes.buffer).getUint32(20);
        }
      }
    },
    document: {baseURI: 'https://example.test/etiket/', body: {appendChild: input => nodes.push(input)},
      createElement: type => type === 'input' ? new Input() : (() => { const canvas = {
        width: 1, height: 1, getContext: () => ({fillRect() {}, drawImage() {}, clearRect() {},
          scale() {}, translate() {}, rotate() {}, setTransform() {}, putImageData() {},
          getImageData: (x, y, w, h) => ({data: new Uint8ClampedArray(w * h * 4).fill(255)})}),
        toBlob: callback => callback(new Blob([new Uint8Array(32)], {type: 'image/jpeg'}))
      }; canvases.push(canvas); return canvas; })()},
    Tesseract: {createWorker: async (langs, oem, opts) => {
      initialized++; options = opts;
      optionsHistory.push(opts);
      const raw = new context.Worker(opts.workerPath);
      assert.deepEqual(Array.from(langs), ['tur', 'eng']);
      assert.equal(oem, 1);
      if (creation) await creation;
      return {setParameters: async () => {},
        recognize: async image => { recognizedBlob = image; options.logger({status: 'recognizing text', progress: 0.5}); return {data: {text: result, confidence}}; },
        terminate: async () => { raw.terminate(); }};
    }}
  });
  vm.runInContext(bridgeSource, context);
  const bridge = context.dokuOcr;
  return {bridge, context, nodes, revoked, blobs, workers, listeners, optionsHistory, canvases, imageSources,
    get recognizedBlob() { return recognizedBlob; },
    get decoded() { return decoded; }, get initialized() { return initialized; }, get options() { return options; },
    set creation(value) { creation = value; }, set result(value) { result = value; },
    set confidence(value) { confidence = value; },
    async upload(file = png()) {
      const picking = bridge.pick(false);
      nodes[0].files = [file];
      await nodes[0].emit('change');
      return picking;
    }};
}

test('upload normalizes locally; release/dispose revoke every owned URL', async () => {
  const s = setup(), photo = await s.upload();
  assert.equal(s.nodes.length, 0);
  assert.equal(s.revoked.length, 1);
  assert.equal(s.blobs.size, 1);
  assert.ok(photo.bytes instanceof Uint8Array);
  s.bridge.release(photo.path); s.bridge.release(photo.path);
  assert.equal(s.blobs.size, 0); assert.equal(s.revoked.length, 2);
  await s.upload(); s.bridge.dispose();
  assert.equal(s.blobs.size, 0);
});
test('capture only on secure mobile; desktop and unsupported fail with upload fallback', async () => {
  for (const config of [{}, {mobile: true, secure: false}, {supported: false}]) {
    const s = setup(config);
    assert.equal(s.bridge.cameraAvailable, false);
    await assert.rejects(s.bridge.pick(true), {message: config.supported === false ? 'unsupported' : 'unavailableCamera'});
    s.bridge.dispose();
  }
  const s = setup({mobile: true});
  const picking = s.bridge.pick(true);
  assert.equal(s.nodes[0].capture, 'environment');
  assert.equal(s.nodes[0].accept, 'image/*');
  await s.nodes[0].emit('cancel');
  assert.equal(await picking, null);
  assert.equal(s.nodes.length, 0);
});
test('picker denial and duplicate are safe; cancel disposes pending picker', async () => {
  const s = setup();
  const create = s.context.document.createElement;
  s.context.document.createElement = type => { const el = create(type); el.denied = true; return el; };
  await assert.rejects(s.bridge.pick(false), {message: 'permission'});
  assert.equal(s.nodes.length, 0);
  s.context.document.createElement = create;
  const pending = s.bridge.pick(false);
  await assert.rejects(s.bridge.pick(false), {message: 'busy'});
  s.bridge.cancelSelection();
  assert.equal(await pending, null);
  assert.equal(s.nodes.length, 0);
});
test('bad, empty, byte-heavy and pixel-heavy images rejected before decoding', async () => {
  const s = setup();
  for (const [file, message] of [
    [new File([], 'empty.png', {type: 'image/png'}), 'invalidPhoto'],
    [new File(['bad'], 'bad.png', {type: 'image/png'}), 'invalidPhoto'],
    [new File([new Uint8Array(20 * 1024 * 1024 + 1)], 'big.png', {type: 'image/png'}), 'tooLarge'],
    [png(10000, 10000), 'tooLarge'], [png(0, 200), 'invalidPhoto']
  ]) { await assert.rejects(s.upload(file), {message}); }
  assert.equal(s.decoded, 0);
  assert.equal(s.blobs.size, 0);
});
test('real worker paths inherit /etiket/; worker is reused and both calls report progress', async () => {
  const s = setup(), p = await s.upload(), messages = [];
  for (let i = 0; i < 2; i++) {
    assert.match(await s.bridge.recognize(p.path, text => messages.push(text)), /Pamuk/);
  }
  assert.equal(s.initialized, 1);
  assert.equal(messages.filter(text => text.includes('%50')).length, 2);
  assert.equal(s.options.workerPath, 'https://example.test/etiket/ocr/worker.min.js');
  assert.equal(s.options.corePath, 'https://example.test/etiket/ocr/core/');
  assert.equal(s.options.langPath, 'https://example.test/etiket/ocr/lang');
  assert.equal(s.options.workerBlobURL, false);
  s.bridge.dispose();
  assert.ok(s.workers[0].stopped);
});
test('cancel during model loading terminates worker, discards old job, permits retry', async () => {
  const s = setup(), p = await s.upload();
  let resolve;
  s.creation = new Promise(done => { resolve = done; });
  const nativeWorker = s.context.Worker;
  const pending = s.bridge.recognize(p.path, () => {});
  assert.equal(s.context.Worker, nativeWorker);
  await assert.rejects(s.bridge.recognize(p.path, () => {}), {message: 'busy'});
  s.bridge.cancelRecognition();
  await assert.rejects(pending, {message: 'canceled'});
  assert.equal(s.workers[0].stopped, true);
  resolve(); s.creation = null;
  assert.match(await s.bridge.recognize(p.path, () => {}), /Pamuk/);
  s.bridge.dispose();
});
test('worker/model failure terminates and permits retry; excessive text is bounded', async () => {
  const s = setup(), p = await s.upload();
  s.creation = Promise.reject(new Error('model download failed'));
  await assert.rejects(s.bridge.recognize(p.path, () => {}), {message: 'modelLoad'});
  assert.equal(s.workers[0].stopped, true);
  s.creation = null; s.result = 'x'.repeat(20001);
  await assert.rejects(s.bridge.recognize(p.path, () => {}), {message: 'tooMuchText'});
  s.result = '7O% mystery fiber';
  assert.equal(await s.bridge.recognize(p.path, () => {}), '7O% mystery fiber');
  s.bridge.dispose();
});
test('pagehide frees resources; BFCache preserves photo and can resume OCR', async () => {
  const s = setup(), p = await s.upload();
  await s.bridge.recognize(p.path, () => {});
  s.listeners.pagehide({persisted: true});
  assert.equal(s.workers[0].stopped, true);
  assert.match(await s.bridge.recognize(p.path, () => {}), /Pamuk/);
  s.listeners.pagehide({persisted: false});
  assert.equal(s.blobs.size, 0);
  await assert.rejects(s.bridge.pick(false), {message: 'unsupported'});
});

test('a canceled worker cannot report progress or terminate a newer worker', async () => {
  const s = setup(), p = await s.upload();
  let firstDone, secondDone;
  s.creation = new Promise(resolve => { firstDone = resolve; });
  const oldRead = s.bridge.recognize(p.path, () => {});
  s.bridge.cancelRecognition();
  await assert.rejects(oldRead, {message: 'canceled'});
  firstDone();
  s.creation = new Promise(resolve => { secondDone = resolve; });
  const progress = [];
  const newRead = s.bridge.recognize(p.path, text => progress.push(text));
  const handled = newRead.then(text => ({text}), error => ({error}));
  const previousCount = progress.length;
  s.optionsHistory[0].logger({status: 'recognizing text', progress: 0.99});
  s.optionsHistory[0].errorHandler('old worker error');
  secondDone();
  const result = await handled;
  assert.equal(progress.length, previousCount + 1); // Only the NEW OCR's %50.
  assert.match(result.text, /Pamuk/);
  assert.equal(s.workers[1].stopped, undefined);
  s.bridge.dispose();
});

// OCR can hallucinate plausible letters on fabric texture, shadows or a blank wall.
// The scanner must not present those as verified textile-label text.
test('empty, texture-like and random high-confidence OCR is rejected as unreadable', async () => {
  const s = setup(), photo = await s.upload();
  for (const [text, confidence] of [
    ['', 0], ['  -  .  / ', 90], ['ooee II ii 4', 24],
    ['QZPJL\nYYNMEZ\nOUIO', 96], ['70% cotton', 18],
    ['2026 COTTON', 96], ['CARE 40°C CO', 97], ['MATERIAL 2026 XYZ', 94],
  ]) {
    s.result = text; s.confidence = confidence;
    await assert.rejects(s.bridge.recognize(photo.path, () => {}), {message: 'emptyText'});
  }
  s.bridge.dispose();
});

test('legible fiber labels, abbreviations and clearly marked unknown fiber survive quality checks', async () => {
  const s = setup(), photo = await s.upload();
  for (const [text, confidence] of [
    ['80% Pamuk\\n20% Polyester', 72],
    ['100% CO', 84],
    ['Lining: Viscose 100%', 64],
    ['Shell: 70% UnknownFiber', 81],
    ['80 PAMUK\\n20 POLYESTER', 69], // OCR may miss percent signs; never guess them.
  ]) {
    s.result = text; s.confidence = confidence;
    assert.equal(await s.bridge.recognize(photo.path, () => {}), text);
  }
  s.bridge.dispose();
});

test('crop validates original-resolution coordinates and does not allocate on invalid requests', async () => {
  const s=setup(), original=png(4000,3000), photo=await s.upload(original);
  assert.equal(photo.sourceWidth,4000); assert.equal(photo.sourceHeight,3000);
  const allocated=s.canvases.length;
  for(const edit of [
    {left:-.1,top:0,width:1,height:1,quarterTurns:0},
    {left:.9,top:0,width:.2,height:1,quarterTurns:0},
    {left:0,top:0,width:0,height:1,quarterTurns:0},
    {left:0,top:0,width:.001,height:1,quarterTurns:0},
    {left:NaN,top:0,width:1,height:1,quarterTurns:0},
    {left:0,top:0,width:1,height:1,quarterTurns:8},
  ]) await assert.rejects(s.bridge.edit(photo.path,edit),{message:'invalidCrop'});
  assert.equal(s.canvases.length,allocated);
  const crop=await s.bridge.edit(photo.path,{left:.1,top:.2,width:.3,height:.4,quarterTurns:1});
  assert.equal(crop.sourceWidth,4000);assert.equal(crop.sourceHeight,3000);
  assert.equal(s.imageSources.at(-1),original,'Crop decodes original, never the resized/JPEG derivative');
  await s.bridge.recognize(crop.path,()=>{});
  assert.equal(s.recognizedBlob,s.blobs.get(crop.path),'OCR receives exact approved preview Blob');
  s.bridge.release(photo.path);s.bridge.release(crop.path);s.bridge.dispose();
  assert.equal(s.blobs.size,0);assert.ok(s.canvases.every(c=>c.width===0&&c.height===0));
});

test('latest crop wins; cancel/dispose prevent late URLs and all canvases are cleared', async () => {
  const s=setup(),photo=await s.upload();
  const older=s.bridge.edit(photo.path,{left:0,top:0,width:.7,height:1,quarterTurns:0});
  const first=assert.rejects(older,{message:'canceled'});
  const latest=await s.bridge.edit(photo.path,{left:0,top:0,width:1,height:.6,quarterTurns:2});
  await first;assert.equal(s.blobs.size,2);
  const abandoned=s.bridge.edit(photo.path,{left:0,top:0,width:.5,height:1,quarterTurns:3});
  s.bridge.cancelEditing();await assert.rejects(abandoned,{message:'canceled'});
  const pending=s.bridge.edit(photo.path,{left:0,top:0,width:1,height:1,quarterTurns:0});
  s.bridge.dispose();await assert.rejects(pending,{message:'canceled'});
  assert.ok(s.canvases.every(c=>c.width===0&&c.height===0));assert.equal(s.blobs.size,0);
  assert.ok(latest.bytes instanceof Uint8Array);
});

test('extreme encoded edges and tiny sources are rejected before image decode', async () => {
  const s=setup();
  await assert.rejects(s.upload(png(32769,32)),{message:'tooLarge'});
  await assert.rejects(s.upload(png(2,1000)),{message:'invalidPhoto'});
  assert.equal(s.decoded,0);assert.equal(s.canvases.length,0);assert.equal(s.blobs.size,0);
});

test('blur invalidates an in-flight edit without discarding the committed source', async () => {
  const s=setup(),photo=await s.upload();
  const pending=s.bridge.edit(photo.path,{left:0,top:0,width:.5,height:.5,quarterTurns:1});
  s.listeners.blur();
  await assert.rejects(pending,{message:'canceled'});
  assert.equal(s.blobs.size,1);await s.bridge.recognize(photo.path,()=>{});
  assert.equal(s.recognizedBlob,s.blobs.get(photo.path));s.bridge.dispose();
  assert.equal(s.blobs.size,0);assert.ok(s.canvases.every(c=>c.width===0&&c.height===0));
});

test('releasing the last session photo clears worker-owned image buffers', async () => {
  const s=setup(),photo=await s.upload();
  await s.bridge.recognize(photo.path,()=>{});
  s.bridge.release(photo.path);
  assert.equal(s.workers[0].stopped,true);
  assert.equal(s.blobs.size,0);
});
