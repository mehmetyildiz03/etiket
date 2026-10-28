import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:etiket/scan/photo_edit.dart';
import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/scan_services_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Future<Uint8List> twoRegionFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 80, 100),
    ui.Paint()..color = const ui.Color(0xffff0000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(80, 0, 80, 100),
    ui.Paint()..color = const ui.Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 100);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(png!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<({int width, int height, int red, int blue})> centerPixel(
  Uint8List encoded,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final center = ((image.height ~/ 2) * image.width +
        image.width ~/ 2) * 4;
    return (
      width: image.width,
      height: image.height,
      red: rgba.getUint8(center),
      blue: rgba.getUint8(center + 2),
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('D4.2 native crop OCR file contains selected source pixels, not whole photo', () async {
    final fixtureDir = await Directory.current.createTemp('native-crop-fixture-');
    final originalFile = File('${fixtureDir.path}/two-regions.png');
    final originalBytes = await twoRegionFixture();
    await originalFile.writeAsBytes(originalBytes);
    final service = NativePhotoSource();
    try {
      final original = await service.adopt(XFile(originalFile.path));
      expect(original.sourceImage, isNotNull);
      expect(original.sourceImage!.width, 160);
      expect(original.sourceImage!.height, 100);
      expect(original.previewBytes, orderedEquals(originalBytes));
      final crops = [
        (edit: const PhotoEdit(left: 0, top: 0, width: .5, height: 1),
          width: 80, height: 100, red: true),
        (edit: const PhotoEdit(left: .5, top: 0, width: .5, height: 1),
          width: 80, height: 100, red: false),
        (edit: const PhotoEdit(left: 0, top: 0, width: 1, height: .5, quarterTurns: 1),
          width: 100, height: 80, red: true),
        (edit: const PhotoEdit(left: 0, top: 0, width: 1, height: .5, quarterTurns: 3),
          width: 100, height: 80, red: false),
      ];
      for (final sample in crops) {
        final crop = await service.editPhoto(original, sample.edit);
        expect(crop.path.endsWith('.png'), isTrue);
        final ocrBytes = await File(crop.path).readAsBytes();
        expect(ocrBytes, orderedEquals(crop.previewBytes),
            reason: 'ML Kit file must be exactly the visible crop PNG');
        final pixel = await centerPixel(ocrBytes);
        expect(pixel.width, sample.width);
        expect(pixel.height, sample.height);
        expect(pixel.red > pixel.blue, sample.red);
        expect(pixel.blue > pixel.red, !sample.red);
        await service.release(crop);
        expect(await File(crop.path).exists(), isFalse);
      }
      await expectLater(
        service.editPhoto(original,
            const PhotoEdit(left: .95, top: 0, width: .5, height: 1)),
        throwsA(isA<ScanFailure>().having(
          (e) => e.kind, 'kind', ScanFailureKind.invalidCrop)),
      );
      expect(await File(original.path).readAsBytes(), orderedEquals(originalBytes));
      await service.release(original);
      expect(await File(original.path).exists(), isFalse);
      expect(await originalFile.exists(), isTrue);
    } finally {
      await fixtureDir.delete(recursive: true);
    }
  });
}
