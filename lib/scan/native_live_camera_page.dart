import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'live_frame_quality.dart';
import 'native_live_timing.dart';
import 'native_center_refocus.dart';
import 'native_camera_recovery.dart';
import 'native_camera_preset_fallback.dart';
import 'native_camera_zoom.dart';
import 'native_frame_luminance.dart';
import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';
import 'native_split_missing_percent.dart';
import 'native_pair_geometry.dart';
import 'native_visible_text_edges.dart';
import 'native_pair_overlay.dart';
import 'native_yuv420_nv21.dart';

/// Android/iOS camera stream. OCR is a temporary, unverified hint only.
/// Never persists or logs video frames, raw OCR, EXIF, or recognized text.
class NativeLiveCameraPage extends StatefulWidget {
  const NativeLiveCameraPage({super.key});

  @override
  State<NativeLiveCameraPage> createState() => _NativeLiveCameraPageState();
}

class _NativeLiveCameraPageState extends State<NativeLiveCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  TextRecognizer? _recognizer;
  Timer? _staleTimer;
  bool _starting = true, _reading = false, _capturing = false,
      _focusing = false, _zooming = false, _closed = false,
      _usingHighStream = false;
  double _zoomLevel = 1.0;
  int _generation = 0, _sequence = 0, _stableFrames = 0;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastResultSample = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _pairs = const [];
  String _fingerprint = '';
  Offset? _lastCenter;
  Map<String, Rect>? _lastPairBoxes;
  Size? _lastOcrImageSize;
  int? _lastPairRotation;
  String _advice = 'Etiketi kameraya getir.';
  String? _error;
  bool _textPresent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _closed || _capturing) return;
      if ((_pairs.isNotEmpty || _textPresent) &&
          !nativeLiveHintFresh(_lastResultSample, DateTime.now())) {
        setState(() {
          _pairs = const [];
          _textPresent = false;
          _fingerprint = '';
          _lastCenter = null;
          _lastPairBoxes = null;
          _lastOcrImageSize = null;
          _lastPairRotation = null;
          _stableFrames = 0;
          _advice = 'Önceki okuma eskidi. Etiketi sabitle ve tekrar odakla.';
        });
      }
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    final token = ++_generation;
    CameraController? controller;
    TextRecognizer? recognizer;
    ResolutionPreset? openedPreset;
    if (mounted) { setState(() { _starting = true; _error = null; }); }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { throw StateError('no camera'); }
      final rear = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final description = rear.isNotEmpty ? rear.first : cameras.first;
      // Some phones can take an ultra-high-resolution still but cannot
      // deliver a continuous ultraHigh video stream. Retry the STREAM at high
      // after releasing the failed controller; still capture remains separate
      // and uses the camera plugin's actual photo pixels, never OCR preview.
      controller = await openNativeCameraWithPresetFallback<CameraController>(
        cancelled: () => !mounted || token != _generation || _closed,
        create: (preset) {
          openedPreset = preset;
          return CameraController(
            description, preset, enableAudio: false,
            imageFormatGroup: Platform.isAndroid
                ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
          );
        },
        initializeAndStart: (attempt) async {
          await attempt.initialize();
          if (!mounted || token != _generation || _closed) {
            throw StateError('camera start cancelled');
          }
          await attempt.startImageStream(_onFrame);
        },
        dispose: (attempt) => attempt.dispose(),
      );
      if (!mounted || token != _generation || _closed) { return; }
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      _controller = controller;
      _recognizer = recognizer;
      _zoomLevel = 1.0;
      // A high-resolution STREAM preset may also reduce takePicture() pixels.
      // Never silently treat its still as the original full-detail capture.
      _usingHighStream = openedPreset != null &&
          nativeStreamRequiresSystemStill(openedPreset!);
      if (mounted && token == _generation) {
        setState(() { _starting = false; _error = null; });
      }
    } catch (_) {
      // startImageStream can fail after initialization. Clear owned handles
      // before finally disposes them, or resumed lifecycle cannot retry.
      if (identical(_controller, controller)) {
        _controller = null;
        _recognizer = null;
      }
      if (mounted && token == _generation && !_closed) {
        setState(() {
          _starting = false;
          _error = 'Canlı kamera açılamadı. Geri dönüp sistem kamerasını veya galeriyi kullan.';
        });
      }
    } finally {
      if (_controller != controller) {
        await controller?.dispose();
      }
      if (_recognizer != recognizer) {
        await recognizer?.close();
      }
    }
  }

  int? _rotationDegrees(CameraController camera) {
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = orientations[camera.value.deviceOrientation];
    if (device == null) return null;
    final sensor = camera.description.sensorOrientation;
    return Platform.isIOS ? sensor :
        camera.description.lensDirection == CameraLensDirection.front
            ? (sensor + device) % 360 : (sensor - device + 360) % 360;
  }

  InputImage? _inputImage(CameraImage frame, int rotationDegrees) {
    if (frame.width <= 0 || frame.height <= 0) return null;

    // CameraX may deliver three YUV_420_888 planes even if NV21 was
    // requested. Convert locally rather than silently losing live OCR.
    // Reject malformed strides and unsupported formats; never guess pixels.
    Uint8List bytes;
    InputImageFormat format;
    int bytesPerRow;
    if (Platform.isAndroid &&
        frame.format.group == ImageFormatGroup.yuv420 &&
        frame.planes.length == 3) {
      final planes = frame.planes;
      final converted = yuv420ToNv21(
        width: frame.width,
        height: frame.height,
        y: YuvPlaneBytes(planes[0].bytes, planes[0].bytesPerRow,
            planes[0].bytesPerPixel ?? 1),
        u: YuvPlaneBytes(planes[1].bytes, planes[1].bytesPerRow,
            planes[1].bytesPerPixel ?? 1),
        v: YuvPlaneBytes(planes[2].bytes, planes[2].bytesPerRow,
            planes[2].bytesPerPixel ?? 1),
      );
      if (converted == null) return null;
      bytes = converted;
      format = InputImageFormat.nv21;
      bytesPerRow = frame.width;
    } else {
      if (frame.planes.length != 1) return null;
      final detected = InputImageFormatValue.fromRawValue(frame.format.raw);
      if (detected == null ||
          (Platform.isAndroid && detected != InputImageFormat.nv21) ||
          (Platform.isIOS && detected != InputImageFormat.bgra8888)) {
        return null;
      }
      bytes = frame.planes.first.bytes;
      format = detected;
      bytesPerRow = frame.planes.first.bytesPerRow;
    }

    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation, format: format, bytesPerRow: bytesPerRow,
      ),
    );
  }

  LiveFrameQuality _quality(CameraImage frame) {
    if (frame.planes.isEmpty) return LiveFrameQuality.unknown;
    final plane = frame.planes.first;
    final isBgra = Platform.isIOS;
    final samples = sampleNativeCenterLuminance(
      bytes: plane.bytes,
      width: frame.width,
      height: frame.height,
      rowStride: plane.bytesPerRow,
      pixelStride: plane.bytesPerPixel ?? (isBgra ? 4 : 1),
      bgra: isBgra,
    );
    return samples == null
        ? LiveFrameQuality.unknown
        : assessLiveLuminance(samples);
  }

  ({List<String> pairs, Offset? center, NativeFramingHint framing,
      Map<String, Rect>? trackedBoxes, Size? imageSize, bool textNearEdge,
      bool missingPercent})
      _extract(RecognizedText recognized, CameraImage frame,
          int rotationDegrees) {
    final pairs = <String>[];
    final boxes = <Rect>[];
    final visibleTextBoxes = <Rect>[];
    final spatialBlocks = <List<NativeOcrLine>>[];
    final pairBoxes = <String, Rect>{};
    var duplicatePair = false;
    var missingPercent = false;
    for (final block in recognized.blocks) {
      final blockLines = <NativeOcrLine>[];
      for (final line in block.lines) {
        blockLines.add(NativeOcrLine(line.text, line.boundingBox));
        // Advisory only: a bare number near a fiber may be a missed tiny '%'.
        // Do not manufacture a pair or let this signal authorize green.
        if (liveMissingPercentNearFiber(line.text)) missingPercent = true;
        if (line.text.trim().isNotEmpty) visibleTextBoxes.add(line.boundingBox);
        final matches = livePairsFromLine(line.text);
        if (matches.isEmpty) continue;
        for (final pair in matches) {
          if (!pairs.contains(pair) && pairs.length < 8) pairs.add(pair);
          if (pairBoxes.containsKey(pair)) {
            duplicatePair = true;
          } else {
            pairBoxes[pair] = line.boundingBox;
          }
        }
        boxes.add(line.boundingBox);
      }
      spatialBlocks.add(blockLines);
    }
    // Use the SAME orientation captured for the ML Kit input. The camera
    // orientation can change while asynchronous OCR is processing.
    // iOS stays on generic guidance until physical preview calibration.
    final dimensions = nativeOcrImageSize(
      width: frame.width, height: frame.height,
      rotationDegrees: rotationDegrees, android: Platform.isAndroid);
    // Only literal, one-to-one tokens on the same horizontal OCR-block row.
    // These are transient yellow candidates, never automatically accepted.
    // iOS OCR-space orientation still awaits physical device calibration.
    if (Platform.isAndroid && dimensions != null) {
      for (final blockLines in spatialBlocks) {
        // ML Kit can split a tiny printed '%' away from a number and fiber.
        // This is a focus warning only; never add an inferred pair.
        if (nativeSplitMissingPercentHint(
            imageSize: dimensions, lines: blockLines)) {
          missingPercent = true;
        }
        for (final candidate in nativeSpatialPairs(
          imageSize: dimensions, lines: blockLines)) {
          if (pairBoxes.containsKey(candidate.value)) {
            duplicatePair = true;
          } else {
            pairBoxes[candidate.value] = candidate.box;
            if (pairs.length < 8) pairs.add(candidate.value);
            boxes.add(candidate.box);
          }
        }
      }
    }
    final geometry = dimensions == null
        ? const NativePairGeometry(null, NativeFramingHint.unknown)
        : assessNativePairGeometry(
            imageSize: dimensions, pairLineBoxes: boxes);
    final trackedBoxes = dimensions == null ? null : normalizeNativePairBoxes(
        imageSize: dimensions, pairBoxes: pairBoxes,
        duplicatePair: duplicatePair);
    final textNearEdge = Platform.isAndroid && dimensions != null &&
        visibleTextTouchesFrameEdge(
          imageSize: dimensions, textLineBoxes: visibleTextBoxes,
          matchedPairCount: pairs.length);
    return (pairs: pairs, center: geometry.center,
        framing: Platform.isAndroid ? geometry.hint : NativeFramingHint.unknown,
        trackedBoxes: trackedBoxes, imageSize: dimensions,
        textNearEdge: textNearEdge, missingPercent: missingPercent);
  }

  void _onFrame(CameraImage frame) {
    if (_closed || _reading || _capturing || _focusing || _zooming ||
        _controller == null ||
        _recognizer == null) { return; }
    final now = DateTime.now();
    if (now.difference(_lastSample).inMilliseconds < 1800) { return; }
    _lastSample = now;
    _reading = true;
    final token = _generation, sequence = ++_sequence;
    unawaited(_readFrame(frame, token, sequence, now));
  }

  Future<void> _readFrame(CameraImage frame, int token, int sequence,
      DateTime started) async {
    try {
      final camera = _controller;
      final recognizer = _recognizer;
      if (camera == null || recognizer == null) { return; }
      final quality = _quality(frame);
      final rotationDegrees = _rotationDegrees(camera);
      final input = rotationDegrees == null ? null : _inputImage(frame, rotationDegrees);
      if (input == null) {
        if (mounted && token == _generation) {
          setState(() {
            _advice = 'Bu kameranın kare biçimi desteklenmiyor. Sistem kamerasını kullan.';
            _pairs = const [];
            _textPresent = false;
            _fingerprint = '';
            _lastCenter = null;
            _lastPairBoxes = null;
            _lastOcrImageSize = null;
            _lastPairRotation = null;
            _stableFrames = 0;
          });
        }
        return;
      }
      final recognized = await recognizer.processImage(input);
      // A rotated phone makes old bounding boxes unsafe for framing hints.
      // Discard the entire stale result; the next sampled frame will retry.
      if (_rotationDegrees(camera) != rotationDegrees) return;
      // OCR results describe the original video sample, not the callback.
      // Reject expired pixels before the spatial matcher and again after it.
      if (!nativeLiveHintFresh(started, DateTime.now())) return;
      final result = _extract(recognized, frame, rotationDegrees!);
      if (!mounted || _closed || _capturing || _focusing || _zooming ||
          token != _generation ||
          !nativeLiveHintFresh(started, DateTime.now()) ||
          sequence != _sequence) { return; }
      final fingerprint = [...result.pairs]..sort();
      final key = fingerprint.join('|');
      final drift = _lastCenter != null && result.center != null &&
          (_lastCenter! - result.center!).distance > .15;
      final withinGap = nativeLiveSamplesWithinGap(_lastResultSample, started);
      // An unresolved bare ratio in the same frame invalidates temporal
      // readiness, even if other percentage-fiber lines were recognized.
      final goodObservation = quality == LiveFrameQuality.usable &&
          result.trackedBoxes != null && !result.missingPercent;
      final stable = goodObservation && key.isNotEmpty &&
          key == _fingerprint && !drift && withinGap &&
          _lastPairRotation == rotationDegrees &&
          nativePairBoxesAgree(_lastPairBoxes, result.trackedBoxes);
      final nextStableFrames = !goodObservation || key.isEmpty
          ? 0 : stable ? _stableFrames + 1 : 1;
      setState(() {
        _pairs = result.pairs;
        _textPresent = recognized.text.trim().isNotEmpty;
        _advice = quality != LiveFrameQuality.usable
            ? liveQualityAdvice(quality)
            : nextStableFrames >= 2 && result.textNearEdge
                ? 'Görünen yazı kadrajın kenarında. Biraz uzaklaş ve etiketi ortala.'
                : result.missingPercent &&
                    result.framing != NativeFramingHint.moveBack
                    ? 'Yüzde işareti küçük veya eksik okunuyor. '
                      'Biraz yakınlaş, yazıya dokunarak odakla ve sabitle.'
                : switch (result.framing) {
                NativeFramingHint.moveBack =>
                  'Yüzde–elyaf satırı kenara yakın. Biraz uzaklaş ve etiketi ortala.',
                NativeFramingHint.moveCloser =>
                  'Yüzde–elyaf satırı küçük. Biraz yakınlaş ve odakla.',
                NativeFramingHint.steady =>
                  'Eşleşen satır görünüyor. Tüm etiketi kadraja al ve sabitle.',
                NativeFramingHint.unknown => liveQualityAdvice(quality),
              };
        _stableFrames = nextStableFrames;
        _fingerprint = goodObservation ? key : '';
        _lastCenter = goodObservation ? result.center : null;
        _lastPairBoxes = goodObservation ? result.trackedBoxes : null;
        _lastOcrImageSize = goodObservation ? result.imageSize : null;
        _lastPairRotation = goodObservation ? rotationDegrees : null;
        _lastResultSample = started;
      });
    } catch (_) {
      if (mounted && token == _generation && !_closed && !_focusing) {
        setState(() {
          _pairs = const [];
          _textPresent = false;
          _fingerprint = '';
          _lastCenter = null;
          _lastPairBoxes = null;
          _lastOcrImageSize = null;
          _lastPairRotation = null;
          _stableFrames = 0;
          _advice = 'Canlı okuma yapılamadı. Sistem kamerasıyla çekmeyi dene.';
        });
      }
    } finally {
      _reading = false;
    }
  }

  /// Explicit user action: request camera hardware to refocus and meter the
  /// central label area. The device may reject either operation. Do not call
  /// this proof of OCR correctness or let old in-flight OCR survive a refocus.
  Future<void> _focusAt(Offset point) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || _closed ||
        _capturing || _focusing || _zooming) { return; }
    final token = ++_generation;
    setState(() {
      _focusing = true;
      _pairs = const [];
      _textPresent = false;
      _fingerprint = '';
      _lastCenter = null;
      _lastPairBoxes = null;
      _lastOcrImageSize = null;
      _lastPairRotation = null;
      _stableFrames = 0;
      _lastResultSample = DateTime.fromMillisecondsSinceEpoch(0);
      _advice = 'Seçilen noktada odak ve ışık ayarı isteniyor…';
    });
    final result = await requestNativeCenterRefocus(
      point: point,
      setFocusPoint: (point) async {
        // Some platforms cannot change the focus mode; a point request can
        // still work. Neither call captures or uploads camera pixels.
        try { await camera.setFocusMode(FocusMode.auto); } catch (_) {}
        await camera.setFocusPoint(point);
      },
      setExposurePoint: camera.setExposurePoint,
    );
    if (!mounted || _closed || _capturing || token != _generation ||
        _controller != camera) { return; }
    setState(() {
      _focusing = false;
      _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
      _advice = switch (result) {
        NativeCenterRefocusResult.focusAndExposureRequested =>
          'Seçilen noktada odak ve ışık ölçümü istendi. Etiketi sabitle; yeni OCR sonucunu bekle.',
        NativeCenterRefocusResult.focusOnlyRequested =>
          'Odak istendi. Işığı elle ayarla ve etiketi sabitle.',
        NativeCenterRefocusResult.exposureOnlyRequested =>
          'Işık ölçümü istendi; odak desteklenmedi. Kamerayı sabitle.',
        NativeCenterRefocusResult.unavailable =>
          'Bu cihazda merkez odak ayarı kullanılamıyor. '
          'Biraz uzaklaşıp yeniden yaklaş veya sistem kamerasını kullan.',
      };
    });
  }

  /// Hardware zoom changes the field of view. Invalidate every previous OCR
  /// observation before changing it; a late callback cannot restore boxes.
  /// This only helps the user aim at small print, never verifies a ratio.
  Future<void> _changeZoom(bool zoomIn) async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || _closed ||
        _capturing || _focusing || _zooming) { return; }
    final token = ++_generation;
    setState(() {
      _zooming = true;
      _pairs = const [];
      _textPresent = false;
      _fingerprint = '';
      _lastCenter = null;
      _lastPairBoxes = null;
      _lastOcrImageSize = null;
      _lastPairRotation = null;
      _stableFrames = 0;
      _lastResultSample = DateTime.fromMillisecondsSinceEpoch(0);
      _advice = 'Kamera yakınlaştırması ayarlanıyor…';
    });
    final outcome = await changeNativeCameraZoom(
      current: _zoomLevel,
      zoomIn: zoomIn,
      getMinZoomLevel: camera.getMinZoomLevel,
      getMaxZoomLevel: camera.getMaxZoomLevel,
      setZoomLevel: camera.setZoomLevel,
    );
    if (!mounted || _closed || _capturing || token != _generation ||
        _controller != camera) { return; }
    setState(() {
      _zooming = false;
      _zoomLevel = outcome.zoom;
      _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
      _advice = switch (outcome.status) {
        NativeZoomStatus.changed =>
          'Yakınlaştırma değişti. Yazıya odakla ve yeni OCR sonucunu bekle.',
        NativeZoomStatus.unchanged =>
          'Kamera yakınlaştırma sınırında. Telefonu uygun mesafede tut.',
        NativeZoomStatus.unavailable =>
          'Bu cihazda kamera yakınlaştırması kullanılamıyor. '
          'Mesafeyi değiştir veya sistem kamerasını kullan.',
      };
    });
  }

  Future<void> _takePicture() async {
    final camera = _controller;
    if (camera == null || _capturing || _closed || _usingHighStream ||
        _focusing || _zooming || !camera.value.isInitialized) { return; }
    setState(() => _capturing = true);
    final captureToken = ++_generation; // Invalidate late preview OCR.
    final outcome = await takeNativeStillWithRecovery<XFile>(
      stopPreview: () async {
        if (camera.value.isStreamingImages) { await camera.stopImageStream(); }
      },
      takeStill: camera.takePicture,
      resumePreview: () async {
        // Never restart a camera after pause, navigation or disposal.
        if (!mounted || _closed || _controller != camera ||
            _generation != captureToken || !camera.value.isInitialized) {
          throw StateError('camera no longer active');
        }
        if (!camera.value.isStreamingImages) {
          await camera.startImageStream(_onFrame);
        }
      },
    );
    if (!mounted || _closed || _generation != captureToken) { return; }
    if (outcome.photo != null) {
      Navigator.of(context).pop(outcome.photo); // Full still; later OCR.
    } else {
      setState(() {
        _capturing = false;
        _error = outcome.streamRecovered
            ? 'Fotoğraf çekilemedi. Kamera yeniden hazır; tekrar dene.'
            : 'Fotoğraf çekilemedi. Geri dönüp sistem kamerasını kullan.';
      });
    }
  }

  Future<void> _shutdown() async {
    ++_generation;
    _focusing = false;
    _zooming = false;
    _zoomLevel = 1.0;
    _pairs = const [];
    _textPresent = false;
    _fingerprint = '';
    _lastCenter = null;
    _lastPairBoxes = null;
    _lastOcrImageSize = null;
    _lastPairRotation = null;
    _stableFrames = 0;
    final camera = _controller;
    final recognizer = _recognizer;
    _controller = null;
    _recognizer = null;
    _usingHighStream = false;
    try {
      if (camera?.value.isStreamingImages ?? false) { await camera!.stopImageStream(); }
    } catch (_) { /* Camera may have already stopped. */ }
    await camera?.dispose();
    await recognizer?.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_shutdown());
    } else if (state == AppLifecycleState.resumed && !_closed &&
        !_capturing && _controller == null) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _closed = true;
    _staleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _controller;
    final available = camera != null && camera.value.isInitialized;
    final hasPairs = _pairs.isNotEmpty;
    final showBoxes = available && canShowNativePairOverlay(
      android: Platform.isAndroid,
      rearCamera: camera.description.lensDirection == CameraLensDirection.back,
      portraitUp: camera.value.deviceOrientation == DeviceOrientation.portraitUp,
      rotationDegrees: _lastPairRotation,
      previewSize: camera.value.previewSize,
      ocrImageSize: _lastOcrImageSize,
      normalizedBoxes: _lastPairBoxes,
      stableFrames: _stableFrames,
    );
    final label = hasPairs ? 'Sarı — doğrulanmamış yüzde ve elyaf adayları'
        : _textPresent ? 'Sarı — yazı algılandı, eşleşme belirsiz'
        : 'Gri — yüzde ve elyaf okunmadı';
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı etiket tarama')),
      body: SafeArea(child: Column(children: [
        Expanded(child: Center(child: available
            ? AspectRatio(
                aspectRatio: 1 / camera.value.aspectRatio,
                child: LayoutBuilder(builder: (context, constraints) =>
                  GestureDetector(
                    // The camera plugin accepts normalized points relative
                    // to the displayed preview. Until physical iOS preview
                    // calibration, taps are Android-only; the accessible
                    // center-focus button remains available on both.
                    onTapDown: Platform.isAndroid && !_capturing && !_focusing && !_zooming
                        ? (details) {
                            final point = nativePreviewTapPoint(
                              details.localPosition,
                              Size(constraints.maxWidth, constraints.maxHeight),
                            );
                            if (point != null) unawaited(_focusAt(point));
                          }
                        : null,
                    child: Stack(fit: StackFit.expand, children: [
                      CameraPreview(camera),
                      if (showBoxes)
                        NativePairOverlay(normalizedBoxes: _lastPairBoxes!),
                    ]),
                  ),
                ),
              )
            : const Icon(Icons.camera_alt_outlined, size: 64))),
        Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(liveRegion: true, child: Text(
              _error ?? (_starting ? 'Kamera açılıyor…' : label),
              style: const TextStyle(fontWeight: FontWeight.bold),
            )),
            if (hasPairs) Text(_pairs.join(' · '),
                key: const ValueKey('native-live-pairs')),
            if (_stableFrames >= 2)
              Text('$_stableFrames ayrı karede benzer adaylar görüldü; doğrulanmadı.'),
            if (showBoxes)
              const Text('Sarı çerçeveler tahmini OCR satır yeridir; kesin doğruluk değildir.',
                  style: TextStyle(fontSize: 12)),
            Text(_advice),
            if (Platform.isAndroid)
              const Text('Yazının bulunduğu yere dokunarak odak ve ışık ölçümü isteyebilirsin.',
                  style: TextStyle(fontSize: 12)),
            if (_usingHighStream)
              const Text('Bu cihazda ultra yüksek çözünürlüklü canlı akış açılamadı. '
                  'Önizleme düşük çözünürlükte çalışıyor. Küçük yüzde işaretlerini '
                  'kaybetmemek için geri dönüp sistem kamerasıyla yüksek '
                  'çözünürlüklü fotoğraf çek.',
                  style: TextStyle(fontSize: 12)),
            const Text('Yeşil hazır değil: tüm etiket görünürlüğü doğrulanmadı. '
                'Fotoğraf sonrası gerçek OCR, metin düzeltmesi ve açık onay gerekir.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: available && !_capturing && !_focusing && !_zooming
                    ? () => _changeZoom(false) : null,
                icon: const Icon(Icons.zoom_out),
                label: const Text('Uzaklaştır'),
              )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${_zoomLevel.toStringAsFixed(1)}×',
                    semanticsLabel: 'Kamera yakınlaştırma düzeyi'),
              ),
              Expanded(child: OutlinedButton.icon(
                onPressed: available && !_capturing && !_focusing && !_zooming
                    ? () => _changeZoom(true) : null,
                icon: const Icon(Icons.zoom_in),
                label: const Text('Yakınlaştır'),
              )),
            ]),
            OutlinedButton.icon(
              onPressed: available && !_capturing && !_focusing && !_zooming
                  ? () => _focusAt(const Offset(0.5, 0.5)) : null,
              icon: const Icon(Icons.center_focus_strong),
              label: Text(_focusing ? 'Odaklanıyor…' : 'Merkeze odakla'),
            ),
            FilledButton.icon(
              onPressed: available && !_capturing && !_focusing && !_zooming
                  ? _usingHighStream
                      ? () => Navigator.of(context).pop()
                      : _takePicture
                  : null,
              icon: const Icon(Icons.camera),
              label: Text(_usingHighStream
                  ? 'Sistem kamerasına dön'
                  : _capturing ? 'Çekiliyor…' : 'Fotoğrafı çek'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Sistem kamerasına / galeriye dön'),
            ),
          ],
        )),
      ])),
    );
  }
}
