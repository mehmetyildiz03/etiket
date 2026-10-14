/* Doku browser OCR bridge. No image/text leaves this browser. */
(() => {
  'use strict';
  const fail = code => new DOMException(code, 'DokuScanError');
  const photos = new Map();
  let picker = null, worker = null, workerOwner = null, job = null, disposed = false;
  const assetBase = new URL('ocr/', document.baseURI);
  const supported = typeof WebAssembly === 'object' && typeof Worker === 'function'
    && typeof FileReader === 'function' && typeof Blob === 'function'
    && !!globalThis.Tesseract;
  const cameraAvailable = supported && globalThis.isSecureContext
    && /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  const stopWorker = () => {
    workerOwner = null;
    if (worker) { worker.terminate().catch(() => {}); worker = null; }
    if (job?.rawWorker) { job.rawWorker.terminate(); job.rawWorker = null; }
  };
  const cancelRecognition = () => {
    if (job) {
      const old = job;
      stopWorker();
      job = null;
      old.reject(fail('canceled'));
    }
  };
  const cancelSelection = () => picker?.finish(null);

  // Check encoded dimensions before allocating a decoded image. Supported
  // camera/upload formats: JPEG, PNG and WebP (HEIC needs local conversion).
  function dimensions(bytes) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (bytes.length >= 24 && view.getUint32(0) === 0x89504e47
      && view.getUint32(4) === 0x0d0a1a0a) {
      return [view.getUint32(16), view.getUint32(20)];
    }
    if (bytes.length > 4 && view.getUint16(0) === 0xffd8) {
      let offset = 2;
      while (offset + 4 <= bytes.length) {
        if (bytes[offset++] !== 0xff) break;
        while (bytes[offset] === 0xff) offset++;
        const marker = bytes[offset++];
        if (marker === 0xda || marker === 0xd9) break;
        if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        if (offset + 2 > bytes.length) break;
        const length = view.getUint16(offset);
        if (length < 2 || offset + length > bytes.length) break;
        if ([0xc0, 0xc1, 0xc2].includes(marker) && length >= 7) {
          return [view.getUint16(offset + 5), view.getUint16(offset + 3)];
        }
        offset += length;
      }
    }
    if (bytes.length >= 30 && view.getUint32(0) === 0x52494646
      && view.getUint32(8) === 0x57454250) {
      const kind = view.getUint32(12);
      if (kind === 0x56503858) { // VP8X
        const uint24 = n => bytes[n] + (bytes[n + 1] << 8) + (bytes[n + 2] << 16);
        return [uint24(24) + 1, uint24(27) + 1];
      }
      if (kind === 0x56503820 && view.getUint16(23) === 0x9d01 && bytes[25] === 0x2a) {
        return [view.getUint16(26, true) & 0x3fff, view.getUint16(28, true) & 0x3fff];
      }
      if (kind === 0x5650384c && bytes[20] === 0x2f) { // VP8L
        const bits = view.getUint32(21, true);
        return [(bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1];
      }
    }
    throw fail('invalidPhoto');
  }

  async function adopt(file) {
    if (!file || !file.size || !file.type.startsWith('image/')) throw fail('invalidPhoto');
    if (file.size > 20 * 1024 * 1024) throw fail('tooLarge');
    const size = dimensions(new Uint8Array(await file.arrayBuffer()));
    if (!size[0] || !size[1]) throw fail('invalidPhoto');
    if (size[0] * size[1] > 24000000) throw fail('tooLarge');
    const original = URL.createObjectURL(file);
    const image = new Image();
    let canvas;
    try {
      image.src = original;
      await image.decode();
      if (!image.naturalWidth || !image.naturalHeight) throw fail('invalidPhoto');
      if (image.naturalWidth * image.naturalHeight > 24000000) throw fail('tooLarge');
      const scale = Math.min(1, 2400 / Math.max(image.naturalWidth, image.naturalHeight));
      canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
      canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
      const context = canvas.getContext('2d');
      context.fillStyle = '#fff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.92));
      if (!blob) throw fail('invalidPhoto');
      const bytes = new Uint8Array(await blob.arrayBuffer());
      if (disposed) throw fail('canceled');
      const path = URL.createObjectURL(blob);
      photos.set(path, blob);
      return {path, bytes};
    } catch (error) {
      throw error instanceof DOMException && error.name === 'DokuScanError'
        ? error : fail('invalidPhoto');
    } finally {
      URL.revokeObjectURL(original);
      image.src = '';
      if (canvas) { canvas.width = 0; canvas.height = 0; }
    }
  }

  function pick(camera) {
    if (!supported || disposed) return Promise.reject(fail('unsupported'));
    if (camera && !cameraAvailable) return Promise.reject(fail('unavailableCamera'));
    if (picker) return Promise.reject(fail('busy'));
    // input.click runs before any await, inside the user's original gesture.
    return new Promise((resolve, reject) => {
      const input = document.createElement('input');
      input.type = 'file'; input.accept = 'image/*';
      input.setAttribute('aria-label', camera ? 'Etiket fotoğrafı çek' : 'Etiket fotoğrafı yükle');
      if (camera) input.setAttribute('capture', 'environment');
      input.style.position = 'fixed'; input.style.left = '-10000px';
      document.body.appendChild(input);
      let finished = false, handling = false, timer;
      const current = {
        finish(result, error) {
          if (finished) return;
          finished = true;
          clearTimeout(timer);
          globalThis.removeEventListener('focus', onFocus);
          input.remove();
          if (picker === current) picker = null;
          error ? reject(error) : resolve(result);
        }
      };
      const onFocus = () => {
        // Older browsers lack `cancel`; allow their change event to arrive first.
        timer = setTimeout(() => {
          if (!handling && !input.files?.length) current.finish(null);
        }, 1500);
      };
      input.addEventListener('cancel', () => current.finish(null), {once: true});
      input.addEventListener('change', async () => {
        if (finished) return;
        handling = true;
        try {
          const file = input.files?.[0];
          const result = file ? await adopt(file) : null;
          if (finished && result) release(result.path);
          else current.finish(result);
        } catch (error) { current.finish(null, error); }
      }, {once: true});
      globalThis.addEventListener('focus', onFocus);
      picker = current;
      try { input.click(); }
      catch (error) {
        current.finish(null, fail(error?.name === 'NotAllowedError' || error?.name === 'SecurityError'
          ? 'permission' : 'invalidPhoto'));
      }
    });
  }

  function release(path) {
    if (photos.delete(path)) URL.revokeObjectURL(path);
  }

  async function recognize(path, progress) {
    if (!supported || disposed) throw fail('unsupported');
    if (!photos.has(path)) throw fail('invalidPhoto');
    if (job) throw fail('busy');
    let rejectSignal;
    const signal = new Promise((_, reject) => { rejectSignal = reject; });
    const current = {reject: rejectSignal, rawWorker: null, progress};
    job = current;
    let loading = !worker;
    const timeout = setTimeout(() => {
      if (job === current) {
        stopWorker();
        current.reject(fail(loading ? 'modelLoad' : 'recognition'));
      }
    }, 120000);
    const run = async () => {
      if (!worker) {
        progress('OCR motoru ve dil modelleri yükleniyor… İlk kullanım için internet gerekir.');
        // Tesseract 6 exposes its worker only AFTER model initialization. Capture
        // the synchronous constructor so cancel/error can terminate it earlier.
        // No async code runs while the constructor is replaced; always restore it.
        const NativeWorker = globalThis.Worker;
        const owner = {};
        workerOwner = owner;
        let starting;
        try {
          globalThis.Worker = class extends NativeWorker {
            constructor(...args) { super(...args); current.rawWorker = this; }
          };
          starting = Tesseract.createWorker(['tur', 'eng'], 1, {
            workerPath: new URL('worker.min.js', assetBase).href,
            corePath: new URL('core/', assetBase).href,
            langPath: new URL('lang/', assetBase).href.replace(/\/$/, ''),
            workerBlobURL: false,
            gzip: true,
            cachePath: 'doku-ocr-6-best-int-v1',
            cacheMethod: 'write',
            logger: message => {
              if (workerOwner !== owner || !job) return;
              const percent = Math.round((message.progress || 0) * 100);
              job.progress(message.status === 'recognizing text'
                ? `Etiket tarayıcında okunuyor… %${percent}`
                : `OCR motoru / dil modeli hazırlanıyor… %${percent}`);
            },
            errorHandler: () => {
              if (workerOwner === owner && job) {
                const active = job;
                const failedWhileLoading = !worker;
                stopWorker();
                active.reject(fail(failedWhileLoading ? 'modelLoad' : 'recognition'));
              }
            }
          });
        } finally { globalThis.Worker = NativeWorker; }
        const created = await starting;
        if (job !== current) { await created.terminate(); throw fail('canceled'); }
        worker = created;
        current.rawWorker = null;
        await worker.setParameters({preserve_interword_spaces: '1'});
      }
      loading = false;
      if (job !== current) throw fail('canceled');
      const result = await worker.recognize(photos.get(path), {}, {text: true});
      if (job !== current) throw fail('canceled');
      const text = result.data.text;
      if (text.length > 20000) throw fail('tooMuchText');
      return text;
    };
    try { return await Promise.race([run(), signal]); }
    catch (error) {
      if (job === current) stopWorker();
      throw error instanceof DOMException && error.name === 'DokuScanError'
        ? error : fail(loading ? 'modelLoad' : 'recognition');
    } finally {
      clearTimeout(timeout);
      if (job === current) job = null;
    }
  }

  function dispose() {
    disposed = true;
    cancelSelection(); cancelRecognition(); stopWorker();
    for (const path of photos.keys()) release(path);
  }
  globalThis.addEventListener('pagehide', event => {
    if (event.persisted) { cancelSelection(); cancelRecognition(); stopWorker(); }
    else dispose();
  });
  const pickSafe = camera => pick(camera).then(photo => ({photo, code: null}),
    error => ({photo: null, code: error.message || 'invalidPhoto'}));
  const recognizeSafe = (path, progress) => recognize(path, progress).then(text => ({text, code: null}),
    error => ({text: null, code: error.message || 'recognition'}));
  globalThis.dokuOcr = Object.freeze({supported, cameraAvailable, pick, recognize, pickSafe, recognizeSafe,
    release, cancelSelection, cancelRecognition, dispose});
})();
