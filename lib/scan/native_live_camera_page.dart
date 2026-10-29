import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'live_frame_quality.dart';
import 'native_frame_luminance.dart';
import 'live_pair_hints.dart';
import 'native_pair_geometry.dart';
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
  bool _starting = true, _reading = false, _capturing = false, _closed = false;
  int _generation = 0, _sequence = 0, _stableFrames = 0;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastResult = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _pairs = const [];
  String _fingerprint = '';
  Offset? _lastCenter;
  Map<String, Rect>? _lastPairBoxes;
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
          DateTime.now().difference(_lastResult).inMilliseconds > 6000) {
        setState(() {
          _pairs = const [];
          _textPresent = false;
          _fingerprint = '';
          _lastCenter = null;
          _lastPairBoxes = null;
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
    if (mounted) { setState(() { _starting = true; _error = null; }); }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { throw StateError('no camera'); }
      final rear = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final description = rear.isNotEmpty ? rear.first : cameras.first;
      controller = CameraController(
        description, ResolutionPreset.ultraHigh, enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted || token != _generation || _closed) { return; }
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      _controller = controller;
      _recognizer = recognizer;
      await controller.startImageStream(_onFrame);
      if (mounted && token == _generation) {
        setState(() { _starting = false; _error = null; });
      }
    } catch (_) {
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
    final samples = sampleNativeLuminance(
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
      Map<String, Rect>? trackedBoxes})
      _extract(RecognizedText recognized, CameraImage frame,
          int rotationDegrees) {
    final pairs = <String>[];
    final boxes = <Rect>[];
    final pairBoxes = <String, Rect>{};
    var duplicatePair = false;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
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
    }
    // Use the SAME orientation captured for the ML Kit input. The camera
    // orientation can change while asynchronous OCR is processing.
    // iOS stays on generic guidance until physical preview calibration.
    final dimensions = nativeOcrImageSize(
      width: frame.width, height: frame.height,
      rotationDegrees: rotationDegrees, android: Platform.isAndroid);
    final geometry = dimensions == null
        ? const NativePairGeometry(null, NativeFramingHint.unknown)
        : assessNativePairGeometry(
            imageSize: dimensions, pairLineBoxes: boxes);
    final trackedBoxes = dimensions == null ? null : normalizeNativePairBoxes(
        imageSize: dimensions, pairBoxes: pairBoxes,
        duplicatePair: duplicatePair);
    return (pairs: pairs, center: geometry.center,
        framing: Platform.isAndroid ? geometry.hint : NativeFramingHint.unknown,
        trackedBoxes: trackedBoxes);
  }

  void _onFrame(CameraImage frame) {
    if (_closed || _reading || _capturing || _controller == null ||
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
      final result = _extract(recognized, frame, rotationDegrees!);
      final elapsed = DateTime.now().difference(started);
      if (!mounted || _closed || _capturing || token != _generation ||
          elapsed.inMilliseconds > 6000 || sequence != _sequence) { return; }
      final fingerprint = [...result.pairs]..sort();
      final key = fingerprint.join('|');
      final drift = _lastCenter != null && result.center != null &&
          (_lastCenter! - result.center!).distance > .15;
      final withinGap = DateTime.now().difference(_lastResult).inMilliseconds <= 5000;
      final goodObservation = quality == LiveFrameQuality.usable &&
          result.trackedBoxes != null;
      final stable = goodObservation && key.isNotEmpty &&
          key == _fingerprint && !drift && withinGap &&
          _lastPairRotation == rotationDegrees &&
          nativePairBoxesAgree(_lastPairBoxes, result.trackedBoxes);
      setState(() {
        _pairs = result.pairs;
        _textPresent = recognized.text.trim().isNotEmpty;
        _advice = quality != LiveFrameQuality.usable
            ? liveQualityAdvice(quality)
            : switch (result.framing) {
                NativeFramingHint.moveBack =>
                  'Yüzde–elyaf satırı kenara yakın. Biraz uzaklaş ve etiketi ortala.',
                NativeFramingHint.moveCloser =>
                  'Yüzde–elyaf satırı küçük. Biraz yakınlaş ve odakla.',
                NativeFramingHint.steady =>
                  'Eşleşen satır görünüyor. Tüm etiketi kadraja al ve sabitle.',
                NativeFramingHint.unknown => liveQualityAdvice(quality),
              };
        _stableFrames = !goodObservation || key.isEmpty
            ? 0 : stable ? _stableFrames + 1 : 1;
        _fingerprint = goodObservation ? key : '';
        _lastCenter = goodObservation ? result.center : null;
        _lastPairBoxes = goodObservation ? result.trackedBoxes : null;
        _lastPairRotation = goodObservation ? rotationDegrees : null;
        _lastResult = DateTime.now();
      });
    } catch (_) {
      if (mounted && token == _generation && !_closed) {
        setState(() {
          _pairs = const [];
          _textPresent = false;
          _fingerprint = '';
          _lastCenter = null;
          _lastPairBoxes = null;
          _lastPairRotation = null;
          _stableFrames = 0;
          _advice = 'Canlı okuma yapılamadı. Sistem kamerasıyla çekmeyi dene.';
        });
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _takePicture() async {
    final camera = _controller;
    if (camera == null || _capturing || _closed || !camera.value.isInitialized) { return; }
    setState(() => _capturing = true);
    ++_generation; // Late preview OCR must not alter the captured photo.
    try {
      if (camera.value.isStreamingImages) { await camera.stopImageStream(); }
      final still = await camera.takePicture();
      if (!mounted || _closed) { return; }
      Navigator.of(context).pop(still); // Full still; OCR is performed later.
    } catch (_) {
      if (mounted && !_closed) {
        setState(() {
          _capturing = false;
          _error = 'Fotoğraf çekilemedi. Geri dönüp sistem kamerasını kullan.';
        });
      }
    }
  }

  Future<void> _shutdown() async {
    ++_generation;
    _pairs = const [];
    _textPresent = false;
    _fingerprint = '';
    _lastCenter = null;
    _lastPairBoxes = null;
    _lastPairRotation = null;
    _stableFrames = 0;
    final camera = _controller;
    final recognizer = _recognizer;
    _controller = null;
    _recognizer = null;
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
    final label = hasPairs ? 'Sarı — doğrulanmamış yüzde ve elyaf adayları'
        : _textPresent ? 'Sarı — yazı algılandı, eşleşme belirsiz'
        : 'Gri — yüzde ve elyaf okunmadı';
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı etiket tarama')),
      body: SafeArea(child: Column(children: [
        Expanded(child: Center(child: available
            ? CameraPreview(camera)
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
            Text(_advice),
            const Text('Yeşil hazır değil: tüm etiket görünürlüğü doğrulanmadı. '
                'Fotoğraf sonrası gerçek OCR, metin düzeltmesi ve açık onay gerekir.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: available && !_capturing ? _takePicture : null,
              icon: const Icon(Icons.camera),
              label: Text(_capturing ? 'Çekiliyor…' : 'Fotoğrafı çek'),
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
