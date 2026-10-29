import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'live_frame_quality.dart';

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
  bool _starting = true, _reading = false, _capturing = false, _closed = false;
  int _generation = 0, _sequence = 0, _stableFrames = 0;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastResult = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _pairs = const [];
  String _fingerprint = '';
  Offset? _lastCenter;
  String _advice = 'Etiketi kameraya getir.';
  String? _error;
  bool _textPresent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final token = ++_generation;
    CameraController? controller;
    TextRecognizer? recognizer;
    if (mounted) setState(() { _starting = true; _error = null; });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('no camera');
      final rear = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final description = rear.isNotEmpty ? rear.first : cameras.first;
      controller = CameraController(
        description, ResolutionPreset.high, enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted || token != _generation || _closed) return;
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

  InputImage? _inputImage(CameraImage frame, CameraController camera) {
    if (frame.planes.length != 1 || frame.width <= 0 || frame.height <= 0) return null;
    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final sensor = camera.description.sensorOrientation;
    final device = orientations[camera.value.deviceOrientation];
    if (device == null) return null;
    final degrees = Platform.isIOS ? sensor :
        camera.description.lensDirection == CameraLensDirection.front
            ? (sensor + device) % 360 : (sensor - device + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(degrees);
    if (rotation == null) return null;
    final plane = frame.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation, format: format, bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  LiveFrameQuality _quality(CameraImage frame) {
    if (frame.planes.isEmpty) return LiveFrameQuality.unknown;
    final bytes = frame.planes.first.bytes;
    final pixelCount = frame.width * frame.height;
    if (pixelCount <= 0) return LiveFrameQuality.unknown;
    final isBgra = Platform.isIOS;
    final step = math.max(1, pixelCount ~/ 512);
    final values = Uint8List((pixelCount / step).ceil());
    var count = 0;
    for (var pixel = 0; pixel < pixelCount; pixel += step) {
      final offset = pixel * (isBgra ? 4 : 1);
      if (offset + (isBgra ? 2 : 0) >= bytes.length) break;
      values[count++] = isBgra
          ? ((bytes[offset] * 0.114) +
              (bytes[offset + 1] * 0.587) +
              (bytes[offset + 2] * 0.299)).round()
          : bytes[offset];
    }
    return assessLiveLuminance(Uint8List.sublistView(values, 0, count));
  }

  static const _fibers =
      'pamuk|cotton|keten|linen|polyester|poliester|viskon|viskoz|viscose|'
      'elastan|elastane|spandex|yün|yun|wool|poliamid|polyamide|nylon|'
      'naylon|akrilik|acrylic|ipek|silk|modal|liyosel|lyocell';
  static final _ratioFirst = RegExp(
    r'(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)\s*(' +
        _fibers + r')(?![a-zA-ZğüşıöçĞÜŞİÖÇ])',
    caseSensitive: false,
  );
  static final _fiberFirst = RegExp(
    r'(' + _fibers + r')\s*(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)',
    caseSensitive: false,
  );

  ({List<String> pairs, Offset? center}) _extract(RecognizedText recognized,
      CameraImage frame) {
    final pairs = <String>[];
    final centers = <Offset>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text;
        final firstRatio = RegExp(r'(?:%\s*\d{1,3}|\d{1,3}\s*%)').firstMatch(text);
        final firstFiber = RegExp(_fibers, caseSensitive: false).firstMatch(text);
        if (firstRatio == null || firstFiber == null) continue;
        final ratioFirst = firstRatio.start <= firstFiber.start;
        final matches = (ratioFirst ? _ratioFirst : _fiberFirst).allMatches(text);
        for (final match in matches) {
          final percent = int.tryParse(ratioFirst
              ? (match.group(1) ?? match.group(2) ?? '')
              : (match.group(2) ?? match.group(3) ?? ''));
          final fiber = match.group(ratioFirst ? 3 : 1)?.toLowerCase();
          if (percent == null || percent <= 0 || percent > 100 || fiber == null) continue;
          final pair = '$percent% $fiber';
          if (!pairs.contains(pair) && pairs.length < 8) pairs.add(pair);
          final box = line.boundingBox;
          if (box.width > 0 && box.height > 0) {
            centers.add(Offset(box.center.dx / frame.width,
                box.center.dy / frame.height));
          }
        }
      }
    }
    final center = centers.isEmpty ? null : Offset(
      centers.map((p) => p.dx).reduce((a, b) => a + b) / centers.length,
      centers.map((p) => p.dy).reduce((a, b) => a + b) / centers.length,
    );
    return (pairs: pairs, center: center);
  }

  void _onFrame(CameraImage frame) {
    if (_closed || _reading || _capturing || _controller == null ||
        _recognizer == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSample).inMilliseconds < 1800) return;
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
      if (camera == null || recognizer == null) return;
      final quality = _quality(frame);
      final input = _inputImage(frame, camera);
      if (input == null) {
        if (mounted && token == _generation) {
          setState(() {
            _advice = 'Bu kameranın kare biçimi desteklenmiyor. Sistem kamerasını kullan.';
            _pairs = const [];
            _stableFrames = 0;
          });
        }
        return;
      }
      final recognized = await recognizer.processImage(input);
      final result = _extract(recognized, frame);
      final elapsed = DateTime.now().difference(started);
      if (!mounted || _closed || _capturing || token != _generation ||
          elapsed.inMilliseconds > 6000 || sequence != _sequence) return;
      final fingerprint = [...result.pairs]..sort();
      final key = fingerprint.join('|');
      final drift = _lastCenter != null && result.center != null &&
          (_lastCenter! - result.center!).distance > .15;
      final withinGap = DateTime.now().difference(_lastResult).inMilliseconds <= 5000;
      final stable = key.isNotEmpty && key == _fingerprint && !drift && withinGap;
      setState(() {
        _pairs = result.pairs;
        _textPresent = recognized.text.trim().isNotEmpty;
        _advice = liveQualityAdvice(quality);
        _stableFrames = key.isEmpty ? 0 : stable ? _stableFrames + 1 : 1;
        _fingerprint = key;
        _lastCenter = result.center;
        _lastResult = DateTime.now();
      });
    } catch (_) {
      if (mounted && token == _generation && !_closed) {
        setState(() {
          _pairs = const [];
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
    if (camera == null || _capturing || _closed || !camera.value.isInitialized) return;
    setState(() => _capturing = true);
    ++_generation; // Late preview OCR must not alter the captured photo.
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final still = await camera.takePicture();
      if (!mounted || _closed) return;
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
    final camera = _controller;
    final recognizer = _recognizer;
    _controller = null;
    _recognizer = null;
    try {
      if (camera?.value.isStreamingImages ?? false) await camera!.stopImageStream();
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
