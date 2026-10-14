import 'dart:async';
import 'dart:typed_data';
import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/web_scan_services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBridge implements BrowserScanBridge {
  @override
  bool supported = true;
  @override
  bool cameraAvailable = false;
  BrowserPhoto? selection;
  String text = 'Dış kumaş\n70% Pamuk\n30% Polyester\nLining\n100% Viscose';
  String? error;
  Completer<String>? pending;
  int canceled = 0, disposed = 0;
  final released = <String>[];
  @override
  Future<BrowserPhoto?> pick(bool camera) async {
    if (error != null) throw BrowserScanException(error!);
    return selection;
  }

  @override
  Future<String> recognize(String path, void Function(String) progress) async {
    progress('Dil modeli indiriliyor…');
    if (error != null) throw BrowserScanException(error!);
    return pending == null ? text : pending!.future;
  }

  @override
  void cancelRecognition() => canceled++;
  @override
  void cancelSelection() {}
  @override
  void dispose() => disposed++;
  @override
  void release(String path) => released.add(path);
}

void main() {
  late FakeBridge bridge;
  late WebPhotoSource photos;
  late WebTextRecognizer ocr;
  late PhotoScanController scan;
  setUp(() {
    bridge = FakeBridge()..selection = BrowserPhoto('blob:local', Uint8List(2));
    photos = WebPhotoSource(bridge);
    ocr = WebTextRecognizer(bridge);
    scan = PhotoScanController(photos, ocr);
  });
  tearDown(() => scan.dispose());

  test(
    'web upload previews, preserves raw TR/EN and never confirms OCR',
    () async {
      expect(photos.galleryLabel, 'Fotoğraf yükle / galeriden seç');
      expect(photos.cameraAvailable, isFalse);
      await scan.pick(PhotoSource.gallery);
      expect(scan.stage, ScanStage.preview);
      await scan.recognize();
      expect(scan.text, bridge.text);
      scan.abandon();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.released, ['blob:local']);
    },
  );
  test(
    'picker cancellation preserves photo and browser permission maps to Turkish',
    () async {
      await scan.pick(PhotoSource.gallery);
      bridge.selection = null;
      await scan.pick(PhotoSource.gallery);
      expect(scan.photo!.path, 'blob:local');
      expect(scan.message, contains('iptal'));
      bridge.error = 'permission';
      await scan.pick(PhotoSource.gallery);
      expect(scan.message, contains('izin'));
    },
  );
  test(
    'unsupported and unavailable camera cannot call browser picker',
    () async {
      await scan.pick(PhotoSource.camera);
      expect(scan.message, contains('Kamera açılamadı'));
      bridge.supported = false;
      await scan.pick(PhotoSource.gallery);
      expect(scan.message, contains('desteklenmiyor'));
    },
  );
  for (final code in [
    'invalidPhoto',
    'tooLarge',
    'modelLoad',
    'recognition',
    'permission',
  ]) {
    test('$code is a safe Turkish failure with retry', () async {
      await scan.pick(PhotoSource.gallery);
      bridge.error = code;
      if (code == 'invalidPhoto' ||
          code == 'tooLarge' ||
          code == 'permission') {
        await scan.pick(PhotoSource.gallery);
      } else {
        await scan.recognize();
      }
      expect(scan.stage, ScanStage.failed);
      expect(scan.message, isNot(contains('blob:')));
      if (code == 'modelLoad') expect(scan.message, contains('internet'));
      bridge.error = null;
      await scan.recognize();
      expect(scan.stage, ScanStage.ready);
    });
  }
  test(
    'progress notifies UI; cancel/edit terminate worker and discard stale OCR',
    () async {
      await scan.pick(PhotoSource.gallery);
      bridge.pending = Completer();
      var notifications = 0;
      scan.onChanged = () => notifications++;
      final reading = scan.recognize();
      expect(ocr.progressMessage, contains('modeli'));
      expect(notifications, greaterThan(1));
      final before = bridge.canceled;
      scan.editText('80% CO 20% PES');
      expect(bridge.canceled, before + 1);
      bridge.pending!.complete('100% WO');
      await reading;
      expect(scan.text, '80% CO 20% PES');
    },
  );
  test(
    'leaving scan stops browser OCR; dispose frees worker/picker resources',
    () async {
      await scan.pick(PhotoSource.gallery);
      bridge.pending = Completer();
      final reading = scan.recognize();
      final before = bridge.canceled;
      scan.abandon();
      expect(bridge.canceled, before + 1);
      bridge.pending!.complete('100% WO');
      await reading;
      expect(bridge.released, ['blob:local']);
      scan.dispose();
      expect(bridge.disposed, 1);
      expect(scan.photo, isNull);
    },
  );
  test(
    'empty and ambiguous web OCR retain existing validation boundaries',
    () async {
      await scan.pick(PhotoSource.gallery);
      bridge.text = '  \n';
      await scan.recognize();
      expect(scan.message, contains('okunabilir yazı'));
      bridge.text = '7O% CO\nmystery fiber';
      await scan.recognize();
      expect(scan.text, bridge.text);
    },
  );
}
