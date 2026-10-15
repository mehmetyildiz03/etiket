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

  // Estimate slight camera tilt from the rows of printed glyphs. A 9-degree
  // skew can otherwise turn 80% into 0% or 100% into 3.00%. This changes only
  // the photo geometry, NEVER the recognized text or percentages.
  function straightenLabel(canvas) {
    const longest = Math.max(canvas.width, canvas.height);
    if (!longest) return 0;
    const scale = Math.min(1, 360 / longest);
    const sample = document.createElement('canvas');
    sample.width = Math.max(1, Math.round(canvas.width * scale));
    sample.height = Math.max(1, Math.round(canvas.height * scale));
    const sw = sample.width, sh = sample.height;
    const sc = sample.getContext('2d', {willReadFrequently: true});
    sc.drawImage(canvas, 0, 0, sw, sh);
    const rgba = sc.getImageData(0, 0, sw, sh).data;
    const luma = new Uint8Array(sw * sh);
    const stride = sw + 1;
    const integral = new Float64Array(stride * (sh + 1));
    for (let y = 0; y < sh; y++) {
      let row = 0;
      for (let x = 0; x < sw; x++) {
        const index = y * sw + x, p = 4 * index;
        const value = Math.round(.299 * rgba[p] + .587 * rgba[p + 1] + .114 * rgba[p + 2]);
        luma[index] = value;
        row += value;
        integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row;
      }
    }
    const ink = new Uint8Array(sw * sh), radius = 9;
    for (let y = 0; y < sh; y++) {
      const top = Math.max(0, y - radius), bottom = Math.min(sh, y + radius + 1);
      for (let x = 0; x < sw; x++) {
        const left = Math.max(0, x - radius), right = Math.min(sw, x + radius + 1);
        const sum = integral[bottom * stride + right] - integral[top * stride + right]
          - integral[bottom * stride + left] + integral[top * stride + left];
        if (luma[y * sw + x] + 12 < sum / ((bottom - top) * (right - left))) {
          ink[y * sw + x] = 1;
        }
      }
    }
    // Exclude large seams, label borders, and backgrounds: only character-sized
    // connected components can vote for the text-line direction.
    const visited = new Uint8Array(sw * sh);
    const queue = new Int32Array(sw * sh);
    const points = [];
    for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
      const first = y * sw + x;
      if (!ink[first] || visited[first]) continue;
      let head = 0, tail = 1;
      queue[0] = first; visited[first] = 1;
      let minX = x, maxX = x, minY = y, maxY = y;
      while (head < tail) {
        const i = queue[head++], cx = i % sw, cy = (i / sw) | 0;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (const n of [cx > 0 ? i - 1 : -1, cx + 1 < sw ? i + 1 : -1,
          cy > 0 ? i - sw : -1, cy + 1 < sh ? i + sw : -1]) {
          if (n >= 0 && ink[n] && !visited[n]) {
            visited[n] = 1; queue[tail++] = n;
          }
        }
      }
      if (tail >= 2 && tail <= 300 && maxX - minX <= 60 && maxY - minY <= 40) {
        for (let k = 0; k < tail; k++) {
          const i = queue[k];
          points.push([i % sw - sw / 2, ((i / sw) | 0) - sh / 2]);
        }
      }
    }
    // Too little text: never rotate a picture based on noise.
    if (points.length < 200) return 0;
    const histogram = new Int32Array(sh + 100);
    const score = degrees => {
      histogram.fill(0);
      const rad = degrees * Math.PI / 180, sine = Math.sin(rad), cosine = Math.cos(rad);
      for (const [x, y] of points) {
        const row = Math.round(x * sine + y * cosine + sh / 2 + 50);
        if (row >= 0 && row < histogram.length) histogram[row]++;
      }
      let total = 0;
      for (const n of histogram) total += n * n;
      return total;
    };
    const straightScore = score(0);
    let bestScore = straightScore, bestAngle = 0;
    for (let angle = -12; angle <= 12; angle += .5) {
      const current = score(angle);
      if (current > bestScore) { bestScore = current; bestAngle = angle; }
    }
    sample.width = sample.height = 0;
    // Require substantial evidence to avoid rotating already-straight labels.
    if (Math.abs(bestAngle) < 2 || bestScore < straightScore * 1.3) return 0;
    const copy = document.createElement('canvas');
    copy.width = canvas.width; copy.height = canvas.height;
    const corrected = copy.getContext('2d');
    corrected.fillStyle = '#fff';
    corrected.fillRect(0, 0, copy.width, copy.height);
    corrected.translate(copy.width / 2, copy.height / 2);
    corrected.rotate(bestAngle * Math.PI / 180);
    corrected.drawImage(canvas, -canvas.width / 2, -canvas.height / 2);
    const target = canvas.getContext('2d');
    target.setTransform(1, 0, 0, 1, 0, 0);
    target.clearRect(0, 0, canvas.width, canvas.height);
    target.drawImage(copy, 0, 0);
    copy.width = copy.height = 0;
    return bestAngle;
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
      straightenLabel(canvas);
      // When the label takes only a small part of a low-resolution picture,
      // percent symbols can turn into "96" (80% => 8096). Give the recognizer
      // enough pixels without inventing or editing any recognized characters.
      const longSide = Math.max(canvas.width, canvas.height);
      if (longSide < 1500) {
        const factor = Math.min(2, 2400 / longSide);
        const enlarged = document.createElement('canvas');
        enlarged.width = Math.round(canvas.width * factor);
        enlarged.height = Math.round(canvas.height * factor);
        const ec = enlarged.getContext('2d');
        ec.imageSmoothingEnabled = true;
        ec.imageSmoothingQuality = 'high';
        ec.drawImage(canvas, 0, 0, enlarged.width, enlarged.height);
        canvas.width = enlarged.width;
        canvas.height = enlarged.height;
        canvas.getContext('2d').drawImage(enlarged, 0, 0);
        enlarged.width = enlarged.height = 0;
      }
      // Preserve small punctuation and accents losslessly; large camera photos
      // still use bounded high-quality JPEG to avoid oversized memory usage.
      const usePng = Math.max(canvas.width, canvas.height) <= 2000;
      const blob = await new Promise(resolve =>
        canvas.toBlob(resolve, usePng ? 'image/png' : 'image/jpeg', 0.95));
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
