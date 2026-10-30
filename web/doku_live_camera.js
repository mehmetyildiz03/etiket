/* Doku live camera: local preview and still capture, never OCR approval.
 * Video frames stay in browser memory; no telemetry, uploads or persistent data.
 */
(function (root, factory) {
  'use strict';
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.dokuLiveCamera = api;
})(globalThis, function (root) {
  'use strict';
  let active = null;
  const error = code => new DOMException(code, 'DokuLiveCameraError');
  const available = () => !!(root.isSecureContext && root.navigator?.mediaDevices?.getUserMedia
    && root.document?.createElement);

  // OCR coordinates describe the sampled video frame. If a device rotates
  // between sampling and rendering, never draw or sample a misleading region.
  // Allow minor canvas rounding only; an axis swap must fail closed.
  function matchesVideoGeometry(video, reading) {
    if (!video || !reading ||
        ![video.videoWidth, video.videoHeight, reading.width, reading.height]
          .every(n => Number.isFinite(n) && n > 0)) return false;
    const ratio = (reading.width / reading.height) /
      (video.videoWidth / video.videoHeight);
    return Number.isFinite(ratio) && Math.abs(ratio - 1) <= .025;
  }

  // Keep the REAL camera still whenever it fits the private OCR limits.
  // A 48MP still used to be discarded in favor of a 1080p video frame. When
  // decoding succeeds, downsample its oriented pixels locally to <=12MP
  // instead: more label detail survives without exceeding the 24MP/20MiB
  // downstream limits. createImageBitmap applies EXIF image orientation;
  // the encoded JPEG is already oriented and contains no original EXIF.
  // Older WebKit/unsupported formats fail closed to the video/system camera.
  async function prepareStill(blob, canvas) {
    if (!blob || !blob.size || blob.size > 32 * 1024 * 1024 ||
        !['image/jpeg', 'image/png', 'image/webp'].includes(blob.type) ||
        typeof root.createImageBitmap !== 'function') return null;
    let bitmap;
    try {
      bitmap = await root.createImageBitmap(blob, {imageOrientation: 'from-image'});
      const width = bitmap?.width, height = bitmap?.height;
      if (![width, height].every(Number.isSafeInteger) ||
          width < 32 || height < 32 || width * height > 100000000 ||
          Math.max(width, height) > 32768) return null;
      if (width * height <= 24000000 && blob.size <= 20 * 1024 * 1024) {
        return blob; // Keep original bytes and full still detail.
      }
      const scale = Math.min(1, 4800 / Math.max(width, height),
        Math.sqrt(12000000 / (width * height)));
      const w = Math.max(1, Math.floor(width * scale));
      const h = Math.max(1, Math.floor(height * scale));
      if (w < 32 || h < 32) return null;
      canvas.width = w; canvas.height = h;
      const context = canvas.getContext('2d');
      if (!context) return null;
      context.drawImage(bitmap, 0, 0, w, h);
      const normalized = await new Promise(resolve =>
        canvas.toBlob(resolve, 'image/jpeg', .92));
      return normalized && normalized.size > 0 &&
        normalized.size <= 20 * 1024 * 1024 &&
        normalized.type === 'image/jpeg' ? normalized : null;
    } catch (_) {
      return null;
    } finally {
      bitmap?.close?.();
      canvas.width = canvas.height = 0;
    }
  }

  function sampleQuality(video, canvas, reading = null) {
    if (!video.videoWidth || !video.videoHeight || video.readyState < 2) return null;
    const scale = 160 / Math.max(video.videoWidth, video.videoHeight);
    const w = Math.max(16, Math.round(video.videoWidth * scale));
    const h = Math.max(16, Math.round(video.videoHeight * scale));
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext('2d', {willReadFrequently: true});
    if (!ctx) return null;
    ctx.drawImage(video, 0, 0, w, h);
    const pixels = ctx.getImageData(0, 0, w, h).data;
    let total = 0, min = 255, max = 0, edges = 0;
    const previous = new Uint8Array(w);
    const lumas = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      let left = 0;
      for (let x = 0; x < w; x++) {
        const p = (y * w + x) * 4;
        const luma = Math.round(.299 * pixels[p] + .587 * pixels[p + 1] + .114 * pixels[p + 2]);
        lumas[y * w + x] = luma;
        total += luma; min = Math.min(min, luma); max = Math.max(max, luma);
        if (x) edges += Math.abs(luma - left);
        if (y) edges += Math.abs(luma - previous[x]);
        previous[x] = luma; left = luma;
      }
    }
    // Sample the actual OCR text region, not only the surrounding garment or
    // dark background. OCR rectangles are unverified and used for advice only.
    // Stale, invalid and tiny regions are ignored; no pixels are persisted.
    let textMetrics = null;
    if (reading && reading.stale === false &&
        matchesVideoGeometry(video, reading)) {
      const source = Array.isArray(reading.pairBoxes) && reading.pairBoxes.length
        ? reading.pairBoxes : reading.boxes;
      const valid = Array.isArray(source) ? source.filter(b => b &&
        [b.x0, b.y0, b.x1, b.y1].every(Number.isFinite) &&
        b.x0 >= 0 && b.y0 >= 0 && b.x1 > b.x0 && b.y1 > b.y0 &&
        b.x1 <= reading.width && b.y1 <= reading.height).slice(0, 24) : [];
      if (valid.length) {
        // A union rectangle spanning separated OCR lines can include mostly
        // background/garment. It can misreport the text as dark or blurred
        // even when each visible line is well lit. Measure each real line
        // independently, then use a robust median for advisory-only hints.
        const lineMetrics = [];
        for (const b of valid) {
          const left = Math.max(0, Math.floor(b.x0 / reading.width * w) - 5);
          const right = Math.min(w, Math.ceil(b.x1 / reading.width * w) + 5);
          const top = Math.max(0, Math.floor(b.y0 / reading.height * h) - 5);
          const bottom = Math.min(h, Math.ceil(b.y1 / reading.height * h) + 5);
          const rw = right - left, rh = bottom - top;
          if (rw < 16 || rh < 16) continue;
          let sum = 0, lo = 255, hi = 0, detail = 0;
          for (let y = top; y < bottom; y++) {
            for (let x = left; x < right; x++) {
              const value = lumas[y * w + x];
              sum += value; lo = Math.min(lo, value); hi = Math.max(hi, value);
              if (x > left) detail += Math.abs(value - lumas[y * w + x - 1]);
              if (y > top) detail += Math.abs(value - lumas[(y - 1) * w + x]);
            }
          }
          lineMetrics.push({meanLuminance: sum / (rw * rh),
            dynamicRange: hi - lo, edgeEnergy: detail / (2 * rw * rh),
            sampleWidth: rw, sampleHeight: rh});
        }
        if (lineMetrics.length) {
          const median = key => {
            const values = lineMetrics.map(m => m[key]).sort((a, b) => a - b);
            const mid = Math.floor(values.length / 2);
            return values.length % 2 ? values[mid] :
              (values[mid - 1] + values[mid]) / 2;
          };
          textMetrics = {meanLuminance: median('meanLuminance'),
            dynamicRange: median('dynamicRange'),
            edgeEnergy: median('edgeEnergy'),
            sampleWidth: Math.round(median('sampleWidth')),
            sampleHeight: Math.round(median('sampleHeight'))};
        }
      }
    }
    // Numeric hints only; neither the text region nor frame verifies OCR.
    return {meanLuminance: total / (w * h), dynamicRange: max - min,
      edgeEnergy: edges / (2 * w * h), sampleWidth: w, sampleHeight: h,
      textMetrics};
  }

  function open() {
    if (!available()) return Promise.reject(error('unsupported'));
    if (active) return Promise.reject(error('busy'));
    const doc = root.document;
    return new Promise((resolve, reject) => {
      let done = false, stream = null, interval = null, capturing = false;
      // Never silently substitute a lower-detail video frame for a failed
      // full-resolution still. The user must explicitly select that option.
      let previewFallbackApproved = false;
      let liveScanner = null, lastMetrics = null, scannerGeneration = 0;
      let torchTrack = null, torchEnabled = false, torchBusy = false;
      const stability = root.dokuLiveStability?.create?.() || null;
      let usingSystemPicker = false;
      let layoutInvalidatedAt = -Infinity;
      let layoutObserver = null;
      const panel = doc.createElement('div');
      panel.setAttribute('role', 'dialog');
      panel.setAttribute('aria-modal', 'true');
      panel.setAttribute('aria-label', 'Doku canlı kamera');
      panel.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#14231e;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:16px;gap:12px;color:#fff;font:16px system-ui,sans-serif';
      const heading = doc.createElement('strong');
      heading.textContent = 'Etiketi çerçeveye yerleştir';
      const video = doc.createElement('video');
      video.autoplay = true; video.muted = true; video.playsInline = true;
      video.setAttribute('playsinline', '');
      video.style.cssText = 'display:block;width:100%;max-width:560px;max-height:65vh;object-fit:contain;box-sizing:border-box;border:3px solid #b4c1b8;border-radius:12px;background:#000';
      const frame = doc.createElement('div');
      frame.style.cssText = 'position:relative;width:100%;max-width:560px;max-height:65vh';
      video.style.maxHeight = '65vh';
      const overlay = doc.createElement('div');
      overlay.setAttribute('aria-hidden', 'true');
      overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;overflow:hidden';
      frame.appendChild(video);
      frame.appendChild(overlay);
      const status = doc.createElement('p');
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      status.style.cssText = 'margin:0;text-align:center;max-width:560px;font-size:14px';
      status.textContent = 'Kamera hazırlanıyor… Canlı OCR henüz etkin değil; çekimden sonra metni doğrula.';
      const adviceFor = (metrics, reading) => {
        const hint = root.dokuCaptureGuidance?.evaluate?.(metrics?.textMetrics || metrics);
        if (hint === 'veryDark') return 'Işığı artır.';
        if (hint === 'veryBright') return 'Parlamayı azalt.';
        if (hint === 'lowDetail') return 'Etiketi yaklaştır ve odakla.';
        // A visible OCR line at the edge suggests possible clipping, not
        // proof that the label is incomplete. Never authorize green here.
        const geometry = root.dokuLiveStability?.geometryHint?.(reading);
        if (geometry === 'edgeText') {
          return 'Görünen yazı kadraj kenarında; biraz uzaklaş ve tüm etiketi göster.';
        }
        if (geometry === 'smallText') {
          return 'Yazılar kadrajda küçük; etikete yaklaş, sabitle ve odakla.';
        }
        return 'Etiketi kadraja al, kamerayı sabit tut.';
      };
      const renderStatus = () => {
        let reading = stability?.view(Date.now()) ||
          {cues: [], textPresent: false, stableFrames: 0, stale: true};
        if (!reading.stale && !matchesVideoGeometry(video, reading)) {
          // A rotated camera invalidates the previous frame's OCR locations
          // and stability; retain still capture and manual verification.
          stability?.clear();
          overlay.replaceChildren();
          reading = stability?.view(Date.now()) ||
            {cues: [], textPresent: false, stableFrames: 0, stale: true};
        }
        const advice = adviceFor(lastMetrics, reading);
        if (reading.stale) overlay.replaceChildren();
        let message;
        if (!liveScanner) {
          message = 'Gri — ' + advice + ' Canlı OCR kullanılamıyor; fotoğraf sonrası doğrula.';
        } else if (reading.cues.length) {
          const pairs = reading.cues.map(cue => cue.percent + '% ' + cue.fiber).join(', ');
          const repeat = reading.stableFrames >= 2
            ? ' ' + reading.stableFrames + ' ayrı OCR karesinde tutarlı göründü; doğrulanmadı.'
            : ' Tek kare adayı; henüz tutarlılık ölçülmedi.';
          message = 'Sarı — doğrulanmamış OCR adayları: ' + pairs + '.' + repeat +
            (reading.moved ? ' Kamerayı sabit tut.' : '') +
            ' Etiketin tamamı henüz doğrulanmadı. ' + advice +
            ' Fotoğraf sonrası kontrol ve açık onay gerekir.';
        } else if (reading.textPresent) {
          message = 'Sarı — yazı var, güvenilir yüzde–elyaf çifti yok. ' + advice;
        } else {
          message = 'Gri — yüzde ve elyaf henüz okunmadı. ' + advice;
        }
        status.style.color = liveScanner && (reading.cues.length || reading.textPresent)
          ? '#ffd45c' : '#c4cbd0';
        if (torchEnabled) message += ' Kamera ışığı açık.';
        // Avoid repeating the same aria-live announcement every 700ms.
        if (status.textContent !== message) status.textContent = message;
      };
      const showBoxes = observation => {
        overlay.replaceChildren();
        if (!matchesVideoGeometry(video, observation) ||
            !video.clientWidth || !video.clientHeight) return;
        const scale = Math.min(video.clientWidth / video.videoWidth,
          video.clientHeight / video.videoHeight);
        const drawnW = video.videoWidth * scale, drawnH = video.videoHeight * scale;
        // The overlay is positioned in the FRAME, while object-fit uses the
        // VIDEO CONTENT box. Account for video layout offsets and borders;
        // otherwise a percentage glyph can be highlighted several pixels
        // away from its actual OCR location on narrow/mobile viewports.
        const contentX = video.offsetLeft + video.clientLeft;
        const contentY = video.offsetTop + video.clientTop;
        if (![contentX, contentY, drawnW, drawnH].every(Number.isFinite)) return;
        const offsetX = contentX + (video.clientWidth - drawnW) / 2;
        const offsetY = contentY + (video.clientHeight - drawnH) / 2;
        const paint = (boxes, border) => {
          for (const bb of boxes) {
            const mark = doc.createElement('div');
            mark.style.cssText = 'position:absolute;box-sizing:border-box;border:' +
              border + ';border-radius:3px';
            mark.style.left = (offsetX + bb.x0 / observation.width * drawnW) + 'px';
            mark.style.top = (offsetY + bb.y0 / observation.height * drawnH) + 'px';
            mark.style.width = ((bb.x1 - bb.x0) / observation.width * drawnW) + 'px';
            mark.style.height = ((bb.y1 - bb.y0) / observation.height * drawnH) + 'px';
            overlay.appendChild(mark);
          }
        };
        // Gray dashed = any detected text; yellow solid = same-line
        // percentage+fiber candidate. Neither is a verification signal.
        // A matched pair is yellow, not a duplicate gray+yellow outline.
        // Keep other observed text gray so incomplete labels remain visible.
        const pairBoxes = Array.isArray(observation.pairBoxes) ? observation.pairBoxes : [];
        const otherText = (Array.isArray(observation.boxes) ? observation.boxes : [])
          .filter(b => !pairBoxes.some(p => p.x0 === b.x0 && p.y0 === b.y0 &&
            p.x1 === b.x1 && p.y1 === b.y1));
        paint(otherText, '2px dashed #c4cbd0');
        paint(pairBoxes, '3px solid #ffd45c');
      };
      const actions = doc.createElement('div');
      actions.style.cssText = 'display:flex;flex-wrap:wrap;gap:10px;justify-content:center';
      const button = (label, action) => {
        const node = doc.createElement('button');
        node.type = 'button'; node.textContent = label;
        node.style.cssText = 'padding:12px 16px;border-radius:10px;border:1px solid #b4c1b8;background:#f4f2ec;color:#254a3f;font:600 15px system-ui';
        node.addEventListener('click', action);
        actions.appendChild(node);
        return node;
      };
      const input = doc.createElement('input');
      input.type = 'file'; input.accept = 'image/*';
      input.setAttribute('capture', 'environment');
      input.setAttribute('aria-label', 'Sistem kamerasıyla etiket çek');
      input.style.cssText = 'position:absolute;left:-10000px';
      const canvas = doc.createElement('canvas');
      const stopStream = () => {
        if (stream) {
          for (const track of stream.getTracks()) track.stop();
          stream = null;
        }
        try { video.pause(); } catch (_) { /* Failed startup. */ }
        video.srcObject = null;
        torchTrack = null;
        torchEnabled = false;
      };
      const close = (value, failure) => {
        if (done) return;
        done = true;
        if (interval !== null) root.clearInterval(interval);
        doc.removeEventListener('visibilitychange', hidden);
        doc.removeEventListener('keydown', onKeyDown);
        root.removeEventListener('pagehide', pagehide);
        root.removeEventListener('resize', invalidateLayout);
        root.visualViewport?.removeEventListener?.('resize', invalidateLayout);
        video.removeEventListener('resize', invalidateLayout);
        video.removeEventListener('loadedmetadata', invalidateLayout);
        layoutObserver?.disconnect();
        liveScanner?.stop(); liveScanner = null;
        stability?.clear();
        stopStream();
        canvas.width = canvas.height = 0;
        panel.remove();
        if (active === session) active = null;
        failure ? reject(failure) : resolve(value);
      };
      const hidden = () => { if (doc.hidden && !usingSystemPicker) close(null); };
      const onKeyDown = event => { if (event.key === 'Escape') close(null); };
      const pagehide = () => close(null);
      // A viewport change invalidates old overlay pixel positions. Wait for
      // new OCR evidence rather than leaving stale boxes over different text.
      const invalidateLayout = () => {
        if (done || usingSystemPicker) return;
        layoutInvalidatedAt = Date.now();
        lastMetrics = null;
        stability?.clear();
        overlay.replaceChildren();
        renderStatus();
      };
      const session = {cancel: () => close(null)};
      active = session;
      // A failed still capture must not permanently disable local live OCR.
      // Create a fresh worker after a failed attempt; the stopped worker can
      // never deliver an accepted result or overwrite manual corrections.
      const startLiveScanner = () => {
        if (done || capturing || usingSystemPicker || !stream || liveScanner) return;
        const generation = ++scannerGeneration;
        liveScanner = root.dokuLiveOcr?.create?.(
          observation => {
            if (generation !== scannerGeneration || done || capturing || usingSystemPicker) return;
            // A pre-resize in-flight OCR result may arrive after the old boxes
            // were cleared. Its duration reveals that sampling started before
            // the resize. Reject it instead of reviving stale coordinates.
            if (layoutInvalidatedAt > -Infinity &&
                (!Number.isFinite(observation?.durationMs) ||
                 Date.now() - observation.durationMs < layoutInvalidatedAt)) return;
            const reading = stability?.observe(observation, Date.now());
            // Ignore late/duplicate observations; render only validated geometry.
            if (reading && !reading.stale && reading.sequence === observation.sequence) {
              showBoxes(reading);
            }
            renderStatus();
          },
          () => {
            if (generation !== scannerGeneration || done) return;
            liveScanner?.stop(); liveScanner = null;
            stability?.clear();
            overlay.replaceChildren();
            renderStatus();
          }
        ) || null;
      };
      // Older Safari/WebKit and other browsers may lack ImageCapture.takePhoto().
      // A video canvas frame can be only 1080p even when the native camera
      // can provide a full-resolution still. On unsupported browsers, make
      // the PRIMARY capture action open the system camera instead of silently
      // passing a lower-resolution preview to OCR.
      const openSystemPicker = () => {
        if (done || usingSystemPicker) return;
        usingSystemPicker = true;
        if (interval !== null) { root.clearInterval(interval); interval = null; }
        liveScanner?.stop(); liveScanner = null;
        stopStream(); // No live camera remains behind the native picker.
        status.textContent = 'Sistem kamerası açılıyor…';
        try { input.click(); } catch (_) { close(null, error('unavailableCamera')); }
      };
      const captureButton = button(
        typeof root.ImageCapture === 'function' ? 'Fotoğrafı çek' : 'Sistem kamerasıyla çek',
        async () => {
        if (typeof root.ImageCapture !== 'function') {
          openSystemPicker();
          return;
        }
        if (capturing || !stream || !video.videoWidth || !video.videoHeight) return;
        capturing = true;
        liveScanner?.stop(); liveScanner = null;
        status.textContent = 'Fotoğraf hazırlanıyor…';
        try {
          let blob = null;
          const track = stream.getVideoTracks()[0];
          if (!previewFallbackApproved && track && typeof root.ImageCapture === 'function') {
            try {
              const candidate = await new root.ImageCapture(track).takePhoto();
              blob = await prepareStill(candidate, canvas);
            } catch (_) { /* Native still unavailable: require an explicit choice. */ }
          }
          if (!blob && !previewFallbackApproved) throw error('stillUnavailable');
          if (!blob && previewFallbackApproved) {
            // A video frame can be much lower resolution than a native still.
            // Only an explicit second press permits this local fallback.
            const width = video.videoWidth, height = video.videoHeight;
            const scale = Math.min(1, 4800 / Math.max(width, height),
              Math.sqrt(24000000 / (width * height)));
            canvas.width = Math.round(width * scale);
            canvas.height = Math.round(height * scale);
            canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
            blob = await new Promise(res => canvas.toBlob(res, 'image/jpeg', .95));
          }
          if (!blob || !blob.size) throw error('invalidPhoto');
          if (done) return;
          close(blob);
        } catch (failure) {
          if (!done) {
            capturing = false;
            stability?.clear();
            overlay.replaceChildren();
            canvas.width = canvas.height = 0;
            startLiveScanner();
            if (failure?.message === 'stillUnavailable') {
              previewFallbackApproved = true;
              captureButton.textContent = 'Video karesini kullan (düşük çözünürlük)';
              status.textContent = 'Yüksek çözünürlüklü fotoğraf alınamadı. Sistem kamerasını kullan veya düşük çözünürlüklü video karesini seç.';
            } else {
              status.textContent = 'Çekim başarısız. Tekrar dene veya sistem kamerasını kullan.';
            }
          }
        }
      });
      // Hardware torch is an optional local camera capability (often absent
      // in Safari). Never request it on unsupported tracks or treat it as OCR
      // confidence. Stopping the track also releases the light.
      const torchButton = button('Kamera ışığını aç', async () => {
        const track = torchTrack;
        if (!track || torchBusy || done || capturing || usingSystemPicker ||
            track.readyState === 'ended') return;
        torchBusy = true;
        torchButton.disabled = true;
        try {
          const next = !torchEnabled;
          await track.applyConstraints({advanced: [{torch: next}]});
          if (done || usingSystemPicker || torchTrack !== track) return;
          torchEnabled = next;
          torchButton.textContent = next ? 'Kamera ışığını kapat' : 'Kamera ışığını aç';
          torchButton.setAttribute('aria-pressed', String(next));
          renderStatus();
        } catch (_) {
          // Some browsers report torch support but reject constraints.
          // Keep preview, OCR and the high-resolution system picker usable.
          if (!done && !usingSystemPicker) {
            torchButton.style.display = 'none';
            status.textContent = 'Kamera ışığı kontrol edilemiyor; ortam ışığını artır veya sistem kamerasını kullan.';
          }
        } finally {
          torchBusy = false;
          torchButton.disabled = false;
        }
      });
      torchButton.style.display = 'none';
      torchButton.setAttribute('aria-pressed', 'false');
      // Never auto-close on focus: native camera can take time to return a
      // file change event. The picker cancel event and İptal close the dialog.
      button('Sistem kamerası (yüksek çözünürlük)', openSystemPicker);
      button('İptal', () => close(null));
      input.addEventListener('change', async () => {
        const original = input.files?.[0] || null;
        if (!original) { close(null); return; }
        // The native system camera can return a 48MP still even on browsers
        // without ImageCapture. The downstream private OCR bridge rejects
        // >24MP or >20MiB inputs; do not lose real label pixels by falling
        // back to the 1080p preview. Normalize the ACTUAL selected still,
        // applying EXIF orientation and bounded local JPEG encoding.
        // If this browser cannot decode it, preserve the original and let
        // the existing OCR bridge report its normal unsupported/size error.
        status.textContent = 'Yüksek çözünürlüklü fotoğraf hazırlanıyor…';
        let prepared = null;
        try { prepared = await prepareStill(original, canvas); }
        catch (_) { /* Keep original if local normalization is unavailable. */ }
        if (!done) close(prepared || original);
      });
      input.addEventListener('cancel', () => close(null));
      actions.appendChild(input);
      panel.appendChild(heading);
      panel.appendChild(frame);
      panel.appendChild(status);
      panel.appendChild(actions);
      doc.body.appendChild(panel);
      doc.addEventListener('visibilitychange', hidden);
      doc.addEventListener('keydown', onKeyDown);
      captureButton.focus?.();
      root.addEventListener('pagehide', pagehide);
      root.addEventListener('resize', invalidateLayout);
      root.visualViewport?.addEventListener?.('resize', invalidateLayout);
      // A camera can renegotiate its intrinsic frame dimensions without a
      // window resize (notably after device rotation or track changes).
      // Likewise a responsive parent can change the displayed video size.
      // Invalidate OCR geometry on either event before drawing more boxes.
      video.addEventListener('resize', invalidateLayout);
      video.addEventListener('loadedmetadata', invalidateLayout);
      if (typeof root.ResizeObserver === 'function') {
        layoutObserver = new root.ResizeObserver(invalidateLayout);
        layoutObserver.observe(video);
      }
      root.navigator.mediaDevices.getUserMedia({audio: false, video: {
        facingMode: {ideal: 'environment'}, width: {ideal: 1920}, height: {ideal: 1080}
      }}).then(got => {
        if (done || usingSystemPicker) { got.getTracks().forEach(track => track.stop()); return; }
        stream = got;
        video.srcObject = stream;
        try {
          const track = got.getVideoTracks()[0];
          if (track && typeof track.applyConstraints === 'function' &&
              track.getCapabilities?.().torch === true) {
            torchTrack = track;
            torchButton.style.display = '';
          }
        } catch (_) { /* Safari or device does not expose torch capability. */ }
        Promise.resolve(video.play()).catch(() => {});
        startLiveScanner();
        renderStatus();
        interval = root.setInterval(() => {
          if (done || capturing) return;
          try {
            lastMetrics = sampleQuality(video, canvas, stability?.view(Date.now()));
            renderStatus();
            // At most one local OCR pass in flight; the scanner drops stale
            // timer ticks and uses a separate bounded 1200px frame.
            if (!doc.hidden) void liveScanner?.sample(video);
          } catch (_) {
            status.textContent = 'Gri — kamera kalitesi ölçülemedi. Fotoğraf sonrası doğrula.';
          }
        }, 700);
      }, e => {
        close(null, error(e?.name === 'NotAllowedError' || e?.name === 'SecurityError'
          ? 'permission' : 'unavailableCamera'));
      });
    });
  }
  return Object.freeze({get available() { return available(); }, open,
    cancel() { active?.cancel(); }, sampleQuality});
});
