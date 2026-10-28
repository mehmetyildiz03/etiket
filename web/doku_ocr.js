/* Doku browser OCR bridge. No image/text leaves this browser. */
(() => {
  'use strict';
  const fail = code => new DOMException(code, 'DokuScanError');
  const photos = new Map();
  const MAX_EDGE = 2400, MAX_PIXELS = 6000000, MAX_CANVAS_PIXELS = 12000000;
  const canvases = new Map();
  let canvasPixels = 0, editRevision = 0, imageQueue = Promise.resolve();
  const serializedImage = action => {
    const result = imageQueue.then(action, action);
    imageQueue = result.then(() => {}, () => {});
    return result;
  };
  function resizeCanvas(canvas, width, height) {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 0 || height < 0 ||
        width > MAX_EDGE || height > MAX_EDGE || width * height > MAX_PIXELS) throw fail('tooLarge');
    if (canvases.has(canvas)) {
      const total = canvasPixels - canvases.get(canvas) + width * height;
      if (total > MAX_CANVAS_PIXELS) throw fail('tooLarge');
      canvasPixels = total; canvases.set(canvas, width * height);
    }
    canvas.width = width; canvas.height = height;
  }
  function makeCanvas(width, height) {
    const canvas = document.createElement('canvas'); canvases.set(canvas, 0);
    try { resizeCanvas(canvas, width, height); return canvas; }
    catch (error) { canvases.delete(canvas); throw error; }
  }
  function freeCanvas(canvas) {
    if (!canvas) return;
    canvasPixels -= canvases.get(canvas) || 0;
    canvases.delete(canvas); canvas.width = canvas.height = 0;
  }
  function rotateExpanded(canvas, radians, border = 24) {
    const w = canvas.width, h = canvas.height;
    // At the 2400px limit a zero-degree border would force a downscale,
    // blending thin % strokes AFTER the pixel-aligned source crop. Keep the
    // exact selected pixels instead; nonzero deskew still needs expanded bounds.
    if (radians === 0 && Math.max(w, h) + 2 * border + 1 > MAX_EDGE) return;
    const sine = Math.abs(Math.sin(radians)), cosine = Math.abs(Math.cos(radians));
    const boundW = w * cosine + h * sine, boundH = w * sine + h * cosine;
    const scale = Math.min(1, (MAX_EDGE - 2 * border - 1) / Math.max(boundW, boundH));
    const width = Math.ceil(boundW * scale) + 2 * border;
    const height = Math.ceil(boundH * scale) + 2 * border;
    const copy = makeCanvas(width, height);
    try {
      const c = copy.getContext('2d');
      c.fillStyle = '#fff'; c.fillRect(0, 0, width, height);
      c.translate(width / 2, height / 2); c.rotate(radians); c.scale(scale, scale);
      c.drawImage(canvas, -w / 2, -h / 2);
      resizeCanvas(canvas, width, height);
      canvas.getContext('2d').drawImage(copy, 0, 0);
    } finally { freeCanvas(copy); }
  }
  const cancelEditing = () => { ++editRevision; };
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
    const sample = makeCanvas(Math.max(1, Math.round(canvas.width * scale)),
      Math.max(1, Math.round(canvas.height * scale)));
    try {
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
    // Require substantial evidence to avoid rotating already-straight labels.
    if (Math.abs(bestAngle) < 2 || bestScore < straightScore * 1.3) return 0;
    rotateExpanded(canvas, bestAngle * Math.PI / 180);
    return bestAngle;
    } finally { freeCanvas(sample); }
  }

  async function withImage(blob, action) {
    const url = URL.createObjectURL(blob), image = new Image();
    let timer;
    try {
      image.src = url;
      await Promise.race([image.decode(), new Promise((_, reject) => {
        timer = setTimeout(() => reject(fail('invalidPhoto')), 15000);
      })]);
      if (!image.naturalWidth || !image.naturalHeight) throw fail('invalidPhoto');
      if (image.naturalWidth * image.naturalHeight > 24000000 ||
          Math.max(image.naturalWidth,image.naturalHeight) > 32768) throw fail('tooLarge');
      return await action(image);
    } finally { clearTimeout(timer); URL.revokeObjectURL(url); image.src = ''; }
  }
  const encode = (canvas, type = 'image/png') => new Promise((resolve, reject) =>
    canvas.toBlob(blob => blob ? resolve(blob) : reject(fail('invalidPhoto')), type, .95));

  function validateEdit(source, edit) {
    if (!edit || !Number.isInteger(edit.quarterTurns) || edit.quarterTurns < 0 || edit.quarterTurns > 3 ||
        ![edit.left, edit.top, edit.width, edit.height].every(Number.isFinite) ||
        edit.left < 0 || edit.top < 0 || edit.width <= 0 || edit.height <= 0 ||
        edit.left + edit.width > 1.000000001 || edit.top + edit.height > 1.000000001) throw fail('invalidCrop');
    const w = edit.quarterTurns % 2 ? source.height : source.width;
    const h = edit.quarterTurns % 2 ? source.width : source.height;
    // Snap BOTH edges to decoded source pixels, including after a quarter turn.
    // Fractional crop translations can resample thin percent glyphs even when
    // the selected region fits at native resolution. Mirror native crop math.
    const left = Math.round(edit.left * w), top = Math.round(edit.top * h);
    const right = Math.round((edit.left + edit.width) * w);
    const bottom = Math.round((edit.top + edit.height) * h);
    const cw = right - left, ch = bottom - top;
    if (cw < 32 || ch < 32 || cw / ch > 40 || ch / cw > 40) throw fail('invalidCrop');
    return {w, h, cw, ch, left, top};
  }
  function readablePreview(canvas, deskewed) {
    // Local mean threshold (Bradley-style) avoids Leptonica selecting a pale
    // color background instead of print when deskew adds white margins.
    // Strong deskewed print uses a gentler 12% threshold to keep percent strokes;
    // faint print uses 25%. Existing strong, unrotated photos stay unchanged.
    // The EXACT monochrome result is previewed before OCR. No text is inferred.
    const w=canvas.width, h=canvas.height, pixels=w*h;
    const stride=Math.ceil(w/4)+1, rows=Math.ceil(h/4)+1;
    if (canvasPixels + pixels + stride*rows > MAX_CANVAS_PIXELS) throw fail('tooLarge');
    const context=canvas.getContext('2d', {willReadFrequently:true});
    const image=context.getImageData(0,0,w,h), data=image.data;
    // 4x4 block sums then an in-place integral image: <= 361,201 uint32s.
    // Sum <= 255 * 5,760,000, safely within uint32; include partial edge blocks.
    const integral=new Uint32Array(stride*rows);
    let darkest=255;
    for(let y=0;y<h;y++) for(let x=0;x<w;x++) {
      const p=(y*w+x)*4;
      const gray=Math.round(.299*data[p]+.587*data[p+1]+.114*data[p+2]);
      darkest=Math.min(darkest,gray);
      integral[(Math.floor(y/4)+1)*stride+Math.floor(x/4)+1]+=gray;
    }
    // Keep strong, unrotated print untouched. Interpolation during deskew can
    // otherwise make a percent glyph read as 96 even in high-contrast print.
    if ((!deskewed && darkest < 16) || darkest > 220) return;
    for(let y=1;y<rows;y++) {
      let sum=0;
      for(let x=1;x<stride;x++) {
        sum+=integral[y*stride+x];
        integral[y*stride+x]=sum+integral[(y-1)*stride+x];
      }
    }
    for(let y=0;y<h;y++) {
      const top=Math.max(0,Math.floor(y/4)-12), bottom=Math.min(rows-1,Math.floor(y/4)+13);
      for(let x=0;x<w;x++) {
        const left=Math.max(0,Math.floor(x/4)-12), right=Math.min(stride-1,Math.floor(x/4)+13);
        const sum=integral[bottom*stride+right]-integral[top*stride+right]
          -integral[bottom*stride+left]+integral[top*stride+left];
        const mean=sum/((Math.min(w,right*4)-left*4)*(Math.min(h,bottom*4)-top*4));
        const p=(y*w+x)*4;
        const gray=Math.round(.299*data[p]+.587*data[p+1]+.114*data[p+2]);
        const value=gray<mean-Math.max(8,mean*(darkest<16?.12:.25))?0:255;
        data[p]=data[p+1]=data[p+2]=value;
      }
    }
    context.putImageData(image,0,0);
  }
  // Sample the exact selected crop BEFORE deskew, enlargement or thresholding.
  // This is diagnostic evidence only; never silently changes OCR or a percentage.
  function frameQuality(canvas) {
    const measure = globalThis.dokuQuality?.measureFrame;
    if (typeof measure !== 'function') return null;
    const longest = Math.max(canvas.width, canvas.height);
    const factor = Math.min(1, 256 / longest);
    const width = Math.round(canvas.width * factor);
    const height = Math.round(canvas.height * factor);
    if (width < 16 || height < 16) return null;
    let sample;
    try {
      sample = makeCanvas(width, height);
      const context = sample.getContext('2d', {willReadFrequently:true});
      context.drawImage(canvas, 0, 0, width, height);
      return measure({data:context.getImageData(0, 0, width, height).data, width, height});
    } catch (_) {
      // Quality measurement must not turn an otherwise readable photo into an error.
      return null;
    } finally { freeCanvas(sample); }
  }

  async function renderPhoto(source, edit, decodedImage = null) {
    const {cw, ch, left, top} = validateEdit(source, edit);
    const render = async image => {
      if (image.naturalWidth !== source.width || image.naturalHeight !== source.height) throw fail('invalidPhoto');
      const factor = Math.min(1, MAX_EDGE / Math.max(cw, ch));
      const canvas = makeCanvas(Math.max(1, Math.round(cw * factor)), Math.max(1, Math.round(ch * factor)));
      try {
        const c = canvas.getContext('2d');
        c.fillStyle = '#fff'; c.fillRect(0, 0, canvas.width, canvas.height);
        // At 1:1 scale use exact source pixels. For downscaled crops keep
        // smoothing; neither setting alters the user's selected rectangle.
        c.imageSmoothingEnabled = factor < 1;
        if (factor < 1) c.imageSmoothingQuality = 'high';
        c.scale(factor, factor); c.translate(-left, -top);
        if (edit.quarterTurns === 1) { c.translate(source.height, 0); c.rotate(Math.PI / 2); }
        else if (edit.quarterTurns === 2) { c.translate(source.width, source.height); c.rotate(Math.PI); }
        else if (edit.quarterTurns === 3) { c.translate(0, source.width); c.rotate(-Math.PI / 2); }
        c.drawImage(image, 0, 0);
        const quality = frameQuality(canvas);
        // Deskew only the selected region; no second hidden preprocessing in OCR.
        const angle = straightenLabel(canvas);
        if (!angle) rotateExpanded(canvas, 0);
        const longSide = Math.max(canvas.width, canvas.height);
        if (longSide < 1500) {
          const scale = Math.min(2, MAX_EDGE / longSide);
          const enlarged = makeCanvas(Math.round(canvas.width * scale), Math.round(canvas.height * scale));
          try {
            const ec = enlarged.getContext('2d');
            ec.imageSmoothingEnabled = true; ec.imageSmoothingQuality = 'high';
            ec.drawImage(canvas, 0, 0, enlarged.width, enlarged.height);
            resizeCanvas(canvas, enlarged.width, enlarged.height);
            canvas.getContext('2d').drawImage(enlarged, 0, 0);
          } finally { freeCanvas(enlarged); }
        }
        readablePreview(canvas, Boolean(angle));
        return {blob: await encode(canvas), quality};
      } finally { freeCanvas(canvas); }
    };
    return decodedImage ? render(decodedImage) : withImage(source.blob, render);
  }
  async function publish(source, blob, current = () => true, quality = null) {
    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (disposed || !current()) throw fail('canceled');
    // A photo hint is optional metadata, never a gate for OCR or an image edit.
    // Only the bounded numeric metrics are passed; no image/text is transmitted.
    let captureHint = null;
    try {
      const evaluate = globalThis.dokuCaptureGuidance?.evaluate;
      if (typeof evaluate === 'function') {
        const result = evaluate(quality);
        if (['veryDark', 'veryBright', 'lowDetail'].includes(result)) captureHint = result;
      }
    } catch (_) { /* A failed hint must not prevent scanning. */ }
    const path = URL.createObjectURL(blob);
    photos.set(path, {blob, source});
    return {path, bytes, quality, captureHint, sourceBytes: source.preview,
      sourcePreviewUrl: source.previewUrl,
      sourceWidth: source.width, sourceHeight: source.height};
  }
  function adopt(file) {
    return serializedImage(async () => {
      if (!file || !file.size || !file.type.startsWith('image/')) throw fail('invalidPhoto');
      if (file.size > 20 * 1024 * 1024) throw fail('tooLarge');
      const size = dimensions(new Uint8Array(await file.arrayBuffer()));
      if (Math.min(...size) < 32) throw fail('invalidPhoto');
      if (size[0] * size[1] > 24000000 || Math.max(...size) > 32768) throw fail('tooLarge');
      return withImage(file, async image => {
        const width = image.naturalWidth, height = image.naturalHeight;
        if (width < 32 || height < 32) throw fail('invalidPhoto');
        const scale = Math.min(1, 960 / Math.max(width, height));
        const thumbnail = makeCanvas(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)));
        let source;
        try {
          const c = thumbnail.getContext('2d'); c.fillStyle = '#fff'; c.fillRect(0,0,thumbnail.width,thumbnail.height);
          c.drawImage(image,0,0,thumbnail.width,thumbnail.height);
          // Use the same lossless PNG codec as the successfully displayed OCR preview.
          // Safari/WebKit may fail to decode the separate JPEG thumbnail even
          // when the processed PNG renders; never upload or persist this copy.
          const preview = new Uint8Array(await (await encode(thumbnail)).arrayBuffer());
          source = {blob:file, width, height, preview,
            // Safari can display the original photo through its native <img>
            // decoder if Flutter's in-memory image codec fails.
            previewUrl: URL.createObjectURL(new Blob([preview], {type:'image/png'}))};
        } finally { freeCanvas(thumbnail); }
        try {
          const rendered = await renderPhoto(source, {left:0, top:0, width:1, height:1, quarterTurns:0}, image);
          return await publish(source, rendered.blob, () => true, rendered.quality);
        } catch (error) {
          URL.revokeObjectURL(source.previewUrl);
          throw error;
        }
      });
    }).catch(error => { throw error instanceof DOMException && error.name === 'DokuScanError' ? error : fail('invalidPhoto'); });
  }
  function edit(path, options) {
    if (!supported || disposed) return Promise.reject(fail('unsupported'));
    const photo = photos.get(path);
    if (!photo) return Promise.reject(fail('invalidPhoto'));
    try { validateEdit(photo.source, options); } catch (error) { return Promise.reject(error); }
    const revision = ++editRevision;
    cancelRecognition();
    return serializedImage(async () => {
      const current = () => !disposed && revision === editRevision && photos.has(path);
      if (!current()) throw fail('canceled');
      const rendered = await renderPhoto(photo.source, options);
      if (!current()) throw fail('canceled');
      return publish(photo.source, rendered.blob, current, rendered.quality);
    }).catch(error => { throw error instanceof DOMException && error.name === 'DokuScanError' ? error : fail('invalidPhoto'); });
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
    const released = photos.get(path);
    if (photos.delete(path)) {
      URL.revokeObjectURL(path);
      // Edited derivatives share one original; revoke the fallback only
      // after the LAST derivative has been disposed.
      if (released?.source?.previewUrl &&
          ![...photos.values()].some(value => value.source === released.source)) {
        URL.revokeObjectURL(released.source.previewUrl);
      }
      // Tesseract may retain its last page in WASM memory. End it with the
      // photo session; successful reads within the session still reuse it.
      if (!photos.size) { cancelRecognition(); stopWorker(); }
    }
  }

  // Tesseract is a general OCR engine, not a detector of actual fabric labels.
  // A wall, weave or shadow can generate confident-looking stray characters.
  // Require BOTH sufficient model confidence AND independent label evidence.
  // This only accepts/rejects a proposal: never repairs percentages or fibers.
  function plausibleLabelText(text, confidence) {
    if (typeof text !== 'string' || !Number.isFinite(confidence) || confidence < 45) return false;
    const folded = text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
      .toLowerCase().replace(/ı/g, 'i');
    // A year, garment size or care temperature is not a fiber percentage.
    // Never decide "textile label" merely from one material word plus any digit.
    const fullFiber = /\b(?:pamuk|cotton|polyester|poliester|keten|linen|viskon|viskoz|viscose|modal|liyosel|lyocell|yun|wool|ipek|silk|poliamid|polyamide|nylon|naylon|elastan|elastane|spandex|akrilik|acrylic|asetat|acetate|kasmir|cashmere|rayon|bamboo|bambu|tencel)\b/i;
    const shortFiber = /\b(?:co|pes|pet|pl|li|cv|vi|cmd|cly|wo|se|pa|el|ea|pan|pc|ca|ws)\b/i;
    const section = /\b(?:shell|lining|outer|astar|dolgu|filling|padding|composition|bilesim|kumas|fabric|material|fiber|fibre|elyaf)\b/i;
    // Genuine labels can have % before OR after a number, and OCR sometimes
    // replaces one number glyph with O/I. Preserve the raw text for review.
    const markedRatio = /(?:[%％]\s*[0-9OoIl?]{1,3}|[0-9OoIl?]{1,3}(?:[.,]\d{1,2})?\s*[%％])/i;
    if (markedRatio.test(folded)) {
      const known = fullFiber.test(folded) || shortFiber.test(folded);
      const meaningfulWord = /\b[a-z]{4,}\b/.test(folded);
      // Unknown fibers remain reviewable if a section context or recognizable
      // percentage + material name exists. Nothing is automatically verified.
      return known || (meaningfulWord && (section.test(folded) ||
        /(?:[%％]\s*[0-9OoIl?]{1,3}|[0-9OoIl?]{1,3}\s*[%％])\s*[a-z]{4,}|\b[a-z]{4,}\s*[0-9OoIl?]{1,3}\s*[%％]/i.test(folded)));
    }
    // A clearly printed percentage marker may disappear from OCR. Allow a
    // number (1..100) alongside the FULL fiber name, but never a 4-digit year,
    // care temperature, or ambiguous two-letter abbreviation.
    if (confidence < 65 || /\b(?:wash|washing|yikama|care|iron|bleach|tumble)\b/i.test(folded)) return false;
    const cleanLines = folded.split(/[\r\n]+/);
    const number = /\b(?:100|[1-9]\d?|0[1-9])(?:[.,]\d{1,2})?\b/g;
    for (const line of cleanLines) {
      if (!fullFiber.test(line)) continue;
      for (const match of line.matchAll(number)) {
        if (/[°℃]/.test(line.slice(Math.max(0, match.index - 4), match.index + match[0].length + 5))) continue;
        if (fullFiber.test(line.slice(Math.max(0, match.index - 24), match.index + match[0].length + 24))) {
          return true;
        }
      }
    }
    return false;
  }

  // Recognition evidence and fabric policy are separate. Confidence is a model
  // score, not a calibrated probability that the transcription is correct.
  function observationFor(rawText, score) {
    const confidence = Number.isFinite(score) && score >= 0 && score <= 100 ? score : null;
    let decision;
    if (!/[\p{L}\p{N}]/u.test(rawText)) decision = 'noText';
    else if (confidence === null || confidence < 45) decision = 'lowConfidence';
    else if (plausibleLabelText(rawText, confidence)) decision = 'candidate';
    else if (plausibleLabelText(rawText, 100)) decision = 'lowConfidence';
    else decision = 'noComposition';
    return Object.freeze({rawText, confidence, decision,
      acceptedText: decision === 'candidate' ? rawText : null, secondReading: null});
  }

  async function readObservation(path, progress) {
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
        // Pin the primary OCR layout explicitly: Tesseract.js defaults to PSM 6,
        // but a future engine upgrade must not silently turn the PSM 3
        // recovery into a duplicate of the first reading.
        await worker.setParameters({preserve_interword_spaces: '1', tessedit_pageseg_mode: '6'});
      }
      loading = false;
      if (job !== current) throw fail('canceled');
      const result = await worker.recognize(photos.get(path).blob, {}, {text: true});
      if (job !== current) throw fail('canceled');
      const text = result.data.text;
      if (typeof text !== 'string') throw fail('recognition');
      if (text.length > 20000) throw fail('tooMuchText');
      const observation = observationFor(text, result.data.confidence);
      // A marginal candidate uses sparse-text PSM 11 as before. When PSM 6
      // fails to find a composition, try automatic layout PSM 3 once: on
      // synthetic textile labels this segmentation recovered some printed
      // percentages that PSM 6 missed. This is NEVER a verified correction:
      // the first decision, accepted text and user-approval gate stay intact.
      // Extra work is bounded to one local second pass and only shown after
      // the user explicitly opens the diagnostics.
      const alternativePsm = observation.decision === 'candidate'
        ? (observation.confidence < 65 ? '11' : null)
        : '3';
      let secondReading = null;
      if (alternativePsm !== null) {
        try {
          await worker.setParameters({tessedit_pageseg_mode: alternativePsm});
          if (job !== current) throw fail('canceled');
          const second = await worker.recognize(photos.get(path).blob, {}, {text:true});
          if (job !== current) throw fail('canceled');
          const secondText = second.data.text;
          const secondScore = second.data.confidence;
          if (typeof secondText === 'string' && secondText.trim() &&
              secondText !== text && secondText.length <= 20000) {
            secondReading = Object.freeze({
              rawText: secondText,
              confidence: Number.isFinite(secondScore) && secondScore >= 0 && secondScore <= 100
                ? secondScore : null,
              mode: alternativePsm === '11' ? 'sparseText' : 'autoPage'
            });
          }
        } catch (error) {
          if (job !== current) throw fail('canceled');
          // OCR alternatives are best-effort. Never suppress a first-pass
          // result if switching the secondary page segmentation fails.
          stopWorker();
        } finally {
          if (worker && job === current) {
            try { await worker.setParameters({tessedit_pageseg_mode: '6'}); }
            catch (_) { stopWorker(); }
          }
        }
      }
      if (observation.decision !== 'candidate') stopWorker();
      return Object.freeze({...observation, secondReading});
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

  // Keep the existing string/emptyText API for benchmark and older callers.
  // The app consumes recognizeSafe.observation, including rejected raw output.
  async function recognize(path, progress) {
    const observation = await readObservation(path, progress);
    if (observation.decision !== 'candidate') throw fail('emptyText');
    return observation.acceptedText;
  }

  function dispose() {
    disposed = true;
    cancelSelection(); cancelRecognition(); cancelEditing(); stopWorker();
    for (const path of photos.keys()) release(path);
  }
  globalThis.addEventListener('blur', cancelEditing);
  globalThis.addEventListener('pagehide', event => {
    if (event.persisted) { cancelSelection(); cancelRecognition(); cancelEditing(); stopWorker(); }
    else dispose();
  });
  const pickSafe = camera => pick(camera).then(photo => ({photo, code: null}),
    error => ({photo: null, code: error.message || 'invalidPhoto'}));
  const editSafe = (path, options) => edit(path, options).then(photo => ({photo, code:null}),
    error => ({photo:null, code:error.message || 'invalidPhoto'}));
  const recognizeSafe = (path, progress) => readObservation(path, progress).then(observation => ({
    text: observation.acceptedText,
    code: observation.decision === 'candidate' ? null : 'emptyText', observation
  }), error => ({text: null, code: error.message || 'recognition', observation: null}));
  globalThis.dokuOcr = Object.freeze({supported, cameraAvailable, pick, recognize, pickSafe, recognizeSafe, edit, editSafe, cancelEditing,
    release, cancelSelection, cancelRecognition, dispose});
})();
