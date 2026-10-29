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

  function sampleQuality(video, canvas) {
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
    for (let y = 0; y < h; y++) {
      let left = 0;
      for (let x = 0; x < w; x++) {
        const p = (y * w + x) * 4;
        const luma = Math.round(.299 * pixels[p] + .587 * pixels[p + 1] + .114 * pixels[p + 2]);
        total += luma; min = Math.min(min, luma); max = Math.max(max, luma);
        if (x) edges += Math.abs(luma - left);
        if (y) edges += Math.abs(luma - previous[x]);
        previous[x] = luma; left = luma;
      }
    }
    // Numeric hints only; do not infer focus or OCR confidence from sharpness.
    return {meanLuminance: total / (w * h), dynamicRange: max - min,
      edgeEnergy: edges / (2 * w * h), sampleWidth: w, sampleHeight: h};
  }

  function open() {
    if (!available()) return Promise.reject(error('unsupported'));
    if (active) return Promise.reject(error('busy'));
    const doc = root.document;
    return new Promise((resolve, reject) => {
      let done = false, stream = null, interval = null, capturing = false;
      let liveScanner = null, lastMetrics = null;
      const stability = root.dokuLiveStability?.create?.() || null;
      let usingSystemPicker = false;
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
      video.style.cssText = 'display:block;width:100%;max-width:560px;max-height:65vh;object-fit:contain;border:3px solid #b4c1b8;border-radius:12px;background:#000';
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
      const adviceFor = metrics => {
        const hint = root.dokuCaptureGuidance?.evaluate?.(metrics);
        return hint === 'veryDark' ? 'Işığı artır.'
          : hint === 'veryBright' ? 'Parlamayı azalt.'
          : hint === 'lowDetail' ? 'Etiketi yaklaştır ve odakla.'
          : 'Etiketi kadraja al, kamerayı sabit tut.';
      };
      const renderStatus = () => {
        const advice = adviceFor(lastMetrics);
        const reading = stability?.view(Date.now()) ||
          {cues: [], textPresent: false, stableFrames: 0, stale: true};
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
        // Avoid repeating the same aria-live announcement every 700ms.
        if (status.textContent !== message) status.textContent = message;
      };
      const showBoxes = observation => {
        overlay.replaceChildren();
        if (!video.clientWidth || !video.clientHeight) return;
        const scale = Math.min(video.clientWidth / video.videoWidth,
          video.clientHeight / video.videoHeight);
        const drawnW = video.videoWidth * scale, drawnH = video.videoHeight * scale;
        const offsetX = (video.clientWidth - drawnW) / 2;
        const offsetY = (video.clientHeight - drawnH) / 2;
        for (const bb of observation.boxes) {
          const mark = doc.createElement('div');
          mark.style.cssText = 'position:absolute;box-sizing:border-box;border:2px solid #ffd45c;border-radius:3px';
          mark.style.left = (offsetX + bb.x0 / observation.width * drawnW) + 'px';
          mark.style.top = (offsetY + bb.y0 / observation.height * drawnH) + 'px';
          mark.style.width = ((bb.x1 - bb.x0) / observation.width * drawnW) + 'px';
          mark.style.height = ((bb.y1 - bb.y0) / observation.height * drawnH) + 'px';
          overlay.appendChild(mark);
        }
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
      };
      const close = (value, failure) => {
        if (done) return;
        done = true;
        if (interval !== null) root.clearInterval(interval);
        doc.removeEventListener('visibilitychange', hidden);
        doc.removeEventListener('keydown', onKeyDown);
        root.removeEventListener('pagehide', pagehide);
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
      const session = {cancel: () => close(null)};
      active = session;
      const captureButton = button('Fotoğrafı çek', async () => {
        if (capturing || !stream || !video.videoWidth || !video.videoHeight) return;
        capturing = true;
        liveScanner?.stop(); liveScanner = null;
        status.textContent = 'Fotoğraf hazırlanıyor…';
        try {
          let blob = null;
          const track = stream.getVideoTracks()[0];
          if (track && typeof root.ImageCapture === 'function') {
            try { blob = await new root.ImageCapture(track).takePhoto(); }
            catch (_) { /* Not supported on all Safari/Chromium cameras. */ }
          }
          if (!blob) {
            // Video capture has less detail than a native still photo. Offer
            // the system-camera path above for a higher-resolution alternative.
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
        } catch (_) {
          if (!done) { capturing = false; status.textContent = 'Çekim başarısız. Tekrar dene veya sistem kamerasını kullan.'; }
        }
      });
      button('Sistem kamerası (yüksek çözünürlük)', () => {
        // Native camera may return focus well before its file change event.
        // Never auto-close on focus: a slow still photo must not be discarded.
        // Use the input cancel event or the explicit İptal control instead.
        usingSystemPicker = true;
        if (interval !== null) { root.clearInterval(interval); interval = null; }
        liveScanner?.stop(); liveScanner = null;
        stopStream(); // Never keep a live video stream behind native camera UI.
        status.textContent = 'Sistem kamerası açılıyor…';
        try { input.click(); } catch (_) { close(null, error('unavailableCamera')); }
      });
      button('İptal', () => close(null));
      input.addEventListener('change', () => close(input.files?.[0] || null));
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
      root.navigator.mediaDevices.getUserMedia({audio: false, video: {
        facingMode: {ideal: 'environment'}, width: {ideal: 1920}, height: {ideal: 1080}
      }}).then(got => {
        if (done || usingSystemPicker) { got.getTracks().forEach(track => track.stop()); return; }
        stream = got;
        video.srcObject = stream;
        Promise.resolve(video.play()).catch(() => {});
        liveScanner = root.dokuLiveOcr?.create?.(
          observation => {
            if (done || capturing || usingSystemPicker) return;
            const reading = stability?.observe(observation, Date.now());
            // Ignore late/duplicate observations; render only validated geometry.
            if (reading && !reading.stale && reading.sequence === observation.sequence) {
              showBoxes(reading);
            }
            renderStatus();
          },
          () => {
            if (done) return;
            liveScanner?.stop(); liveScanner = null;
            stability?.clear();
            overlay.replaceChildren();
            renderStatus();
          }
        ) || null;
        renderStatus();
        interval = root.setInterval(() => {
          if (done || capturing) return;
          try {
            lastMetrics = sampleQuality(video, canvas);
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
