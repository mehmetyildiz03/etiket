import 'dart:io';
import 'dart:ui' as ui;

import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/native_capture_guidance.dart';
import 'package:etiket/scan/scan_services_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Future<Uint8List> fixturePng([
  ui.Color color = const ui.Color(0xffffffff),
]) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 20, 20),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(20, 20);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class DeniedPicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      throw PlatformException(code: 'camera_access_denied_without_prompt');
}

class RecordingPicker extends ImagePicker {
  RecordingPicker(this.file);
  final XFile file;
  ImageSource? requestedSource;
  double? requestedMaxWidth;
  double? requestedMaxHeight;
  int? requestedQuality;
  bool? requestedMetadata;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    requestedSource = source;
    requestedMaxWidth = maxWidth;
    requestedMaxHeight = maxHeight;
    requestedQuality = imageQuality;
    requestedMetadata = requestFullMetadata;
    return file;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixtures;
  setUp(() async {
    fixtures = await Directory.current.createTemp('scan-fixture-');
  });
  tearDown(() async {
    await fixtures.delete(recursive: true);
  });

  test(
    'native permission errors retain permanent-denial semantics without raw logs',
    () async {
      final source = NativePhotoSource(picker: DeniedPicker());
      await expectLater(
        source.pick(PhotoSource.camera),
        throwsA(
          isA<ScanFailure>()
              .having((e) => e.kind, 'kind', ScanFailureKind.permission)
              .having((e) => e.permanent, 'permanent', true),
        ),
      );
      for (final code in ['camera_access_denied', 'photo_access_denied']) {
        expect(
          mapPickerError(PlatformException(code: code)).kind,
          ScanFailureKind.permission,
        );
      }
      expect(
        mapPickerError(PlatformException(code: 'no_available_camera')).kind,
        ScanFailureKind.unavailableCamera,
      );
    },
  );
  test('D4.2 camera and gallery retain finer glyph pixels without bypassing private bounds', () async {
    final bytes = await fixturePng(); // synthetic only, no user/EXIF data
    expect(
      NativePhotoSource.pickerMaxEdge * NativePhotoSource.pickerMaxEdge,
      lessThanOrEqualTo(NativePhotoSource.maxPixels),
    );
    for (final kind in [PhotoSource.camera, PhotoSource.gallery]) {
      final original = File('${fixtures.path}/${kind.name}.png');
      await original.writeAsBytes(bytes);
      final picker = RecordingPicker(XFile(original.path));
      final source = NativePhotoSource(picker: picker);
      final photo = await source.pick(kind);
      expect(photo, isNotNull);
      expect(
        picker.requestedSource,
        kind == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      );
      expect(picker.requestedMaxWidth, 4000);
      expect(picker.requestedMaxHeight, 4000);
      expect(picker.requestedQuality, isNull);
      expect(picker.requestedMetadata, isFalse);
      expect(photo!.previewBytes, orderedEquals(bytes));
      expect(await File(photo.path).readAsBytes(), orderedEquals(bytes));
      expect(await original.exists(), isTrue);
      await source.release(photo);
      expect(await File(photo.path).exists(), isFalse);
    }
  });

  test('D4.2 native capture hints use only local pixels and never rewrite the original', () async {
    for (final sample in [
      (color: const ui.Color(0xff080808), hint: PhotoCaptureHint.veryDark),
      (color: const ui.Color(0xfff8f8f8), hint: PhotoCaptureHint.veryBright),
      (color: const ui.Color(0xff808080), hint: PhotoCaptureHint.lowDetail),
    ]) {
      final bytes = await fixturePng(sample.color);
      final original = File('${fixtures.path}/${sample.hint.name}.png');
      await original.writeAsBytes(bytes);
      final source = NativePhotoSource();
      final photo = await source.adopt(XFile(original.path));
      expect(photo.captureHint, sample.hint);
      expect(photo.previewBytes, orderedEquals(bytes));
      expect(await File(photo.path).readAsBytes(), orderedEquals(bytes));
      await source.release(photo);
      expect(await original.exists(), isTrue);
      expect(await File(photo.path).exists(), isFalse);
    }
  });

  test('D4.2 native quality guidance fails open on textured or malformed samples', () {
    Uint8List solid(int value) {
      final rgba = Uint8List(64 * 64 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = rgba[i + 1] = rgba[i + 2] = value;
        rgba[i + 3] = 255;
      }
      return rgba;
    }
    final checker = solid(255);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        if ((x + y).isEven) {
          final p = (y * 64 + x) * 4;
          checker[p] = checker[p + 1] = checker[p + 2] = 0;
        }
      }
    }
    expect(nativeCaptureHintFromRgba(checker, 64, 64), isNull);
    expect(nativeCaptureHintFromRgba(Uint8List(4), 64, 64), isNull);
    expect(nativeCaptureHintFromRgba(solid(12), 64, 64),
        PhotoCaptureHint.veryDark);
    expect(nativeCaptureHintFromRgba(solid(245), 64, 64),
        PhotoCaptureHint.veryBright);
  });

  test(
    'validated private copy is deleted, gallery original and unknown files are preserved',
    () async {
      final original = File('${fixtures.path}/gallery.png');
      await original.writeAsBytes(await fixturePng());
      final source = NativePhotoSource();
      final photo = await source.adopt(XFile(original.path));
      expect(await File(photo.path).exists(), isTrue);
      expect(await original.exists(), isTrue);
      expect(() => photo.previewBytes[0] = 0, throwsUnsupportedError);
      await source.release(photo);
      expect(await File(photo.path).exists(), isFalse);
      expect(await original.exists(), isTrue);
      await source.release(
        ScanPhoto(path: original.path, previewBytes: Uint8List(0)),
      );
      expect(await original.exists(), isTrue);
    },
  );
  test('picker cache copy is removed after adopting it', () async {
    final cached = await Directory.systemTemp.createTemp('picker-fixture-');
    try {
      final original = File('${cached.path}/camera.png');
      await original.writeAsBytes(await fixturePng());
      final source = NativePhotoSource();
      final photo = await source.adopt(XFile(original.path));
      expect(await original.exists(), isFalse);
      expect(await File(photo.path).exists(), isTrue);
      await source.release(photo);
      expect(await File(photo.path).exists(), isFalse);
    } finally {
      await cached.delete(recursive: true);
    }
  });

  test(
    'startup cleanup removes orphaned copies while keeping another live scan',
    () async {
      final original = File('${fixtures.path}/active.png');
      await original.writeAsBytes(await fixturePng());
      final first = NativePhotoSource();
      final live = await first.adopt(XFile(original.path));
      final orphan = await Directory.systemTemp.createTemp('doku-scan-');
      await File('${orphan.path}/old-photo').writeAsBytes([1, 2, 3]);
      final other = NativePhotoSource(picker: DeniedPicker());
      await expectLater(
        other.pick(PhotoSource.camera),
        throwsA(isA<ScanFailure>()),
      );
      expect(await orphan.exists(), isFalse);
      expect(await File(live.path).exists(), isTrue);
      await first.release(live);
    },
  );
  test(
    'empty, corrupt and oversized inputs are rejected before recognition',
    () async {
      final source = NativePhotoSource();
      final empty = File('${fixtures.path}/empty');
      await empty.writeAsBytes([]);
      final corrupt = File('${fixtures.path}/corrupt');
      await corrupt.writeAsString('not an image');
      for (final file in [empty, corrupt]) {
        await expectLater(
          source.adopt(XFile(file.path)),
          throwsA(
            isA<ScanFailure>().having(
              (e) => e.kind,
              'kind',
              ScanFailureKind.invalidPhoto,
            ),
          ),
        );
        expect(await file.exists(), isTrue);
      }
      final large = await File(
        '${fixtures.path}/large',
      ).open(mode: FileMode.write);
      await large.truncate(NativePhotoSource.maxBytes + 1);
      await large.close();
      await expectLater(
        source.adopt(XFile('${fixtures.path}/large')),
        throwsA(
          isA<ScanFailure>().having(
            (e) => e.kind,
            'kind',
            ScanFailureKind.tooLarge,
          ),
        ),
      );
    },
  );

  const channel = MethodChannel('google_mlkit_text_recognizer');
  for (final failing in [false, true]) {
    test(
      'ML Kit bridge uses a local file/Latin script and closes on ${failing ? 'failure' : 'success'}',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'vision#startTextRecognizer') {
                if (failing) throw PlatformException(code: 'decode_failure');
                return {'text': '70% CO 30% PES', 'blocks': []};
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final photo = ScanPhoto(
          path: '/private/cache/label-image',
          previewBytes: Uint8List(0),
        );
        final reading = NativeTextRecognizer().recognize(photo);
        if (failing) {
          await expectLater(
            reading,
            throwsA(
              isA<ScanFailure>().having(
                (e) => e.kind,
                'kind',
                ScanFailureKind.recognition,
              ),
            ),
          );
        } else {
          expect(await reading, '70% CO 30% PES');
        }
        expect(calls.map((c) => c.method), [
          'vision#startTextRecognizer',
          'vision#closeTextRecognizer',
        ]);
        expect(calls.first.arguments['script'], 0);
        expect(calls.first.arguments['imageData']['path'], photo.path);
        expect(calls.first.arguments['id'], calls.last.arguments['id']);
      },
    );
  }
}
