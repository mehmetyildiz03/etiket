import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:etiket/scan/photo_edit.dart';
import 'package:etiket/scan/scan_services_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

// Synthetic 160x100 JPEG: red on the left, blue on the right. This is NOT a
// camera/user image. The embedded EXIF orientation is 6 (90 degrees CW).
// Orientation 8 is produced by changing only the TIFF orientation tag.
const _syntheticJpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCABkAKADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFgEBAQEAAAAAAAAAAAAAAAAAAAgG/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AiAGUUAAAAAAAAAiQFVpqAAAAAAAAWwCVFKgAAAAAAAIkBVaagAAAAAAAFsAlRSoAAAAAAACJAVWmoAAAAAAABbAJUUqAAAAAAAAiQFVpqAAAAAAAAWwCVFKgAAAAAAAIkBVaagAAAAAAAFsAlRSoAAAAAAACJAVWmoAAAAAAABbAJUUqAAAAAAAAiQFVpqAAAAAAAAf/2Q==';

Uint8List _jpegWithOrientation(int orientation) {
  final bytes = base64Decode(_syntheticJpeg);
  const tag = [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00];
  var offset = -1;
  for (var i = 0; i < bytes.length - tag.length; i++) {
    if (List.generate(tag.length, (j) => bytes[i + j] == tag[j])
        .every((match) => match)) {
      offset = i + tag.length;
      break;
    }
  }
  if (offset < 0 || bytes[offset] != 6) {
    throw StateError('Synthetic EXIF orientation tag not found');
  }
  bytes[offset] = orientation;
  return bytes;
}

Future<({int width, int height, bool red})> _decodedCenter(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
    final red = rgba.getUint8(offset);
    final blue = rgba.getUint8(offset + 2);
    expect((red - blue).abs(), greaterThan(120));
    return (width: image.width, height: image.height, red: red > blue);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('D4.2 native EXIF 1–8 crop and manual rotation keep source pixels', () async {
    final directory = await Directory.current.createTemp('synthetic-exif-');
    try {
      // The fixture is a synthetic 160x100 JPEG: red on its encoded left,
      // blue on its encoded right. EXIF may mirror, flip or transpose it.
      // These are orientation/crop tests, not real-phone OCR accuracy data.
      for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final bytes = _jpegWithOrientation(orientation);
        final file = File('${directory.path}/exif-$orientation.jpg');
        await file.writeAsBytes(bytes);
        final service = NativePhotoSource();
        final original = await service.adopt(XFile(file.path));
        try {
          final source = original.sourceImage;
          expect(source, isNotNull);
          final sideBySide = orientation <= 4;
          final firstRed = [1, 4, 5, 6].contains(orientation);
          // EXIF 5–8 exchange the image axes. EXIF 2, 4, 5 and 7
          // include mirroring; a mere rotation-only decoder is wrong.
          expect((source!.width, source.height),
              sideBySide ? (160, 100) : (100, 160),
              reason: 'EXIF $orientation must be applied before crop UI');
          final first = await service.editPhoto(
            original,
            sideBySide
                ? const PhotoEdit(left: 0, top: 0, width: .5, height: 1)
                : const PhotoEdit(left: 0, top: 0, width: 1, height: .5),
          );
          final second = await service.editPhoto(
            original,
            sideBySide
                ? const PhotoEdit(left: .5, top: 0, width: .5, height: 1)
                : const PhotoEdit(left: 0, top: .5, width: 1, height: .5),
          );
          // After an additional 90° user rotation, the same physical
          // halves move to a different axis; this exercises EXIF + editor
          // transforms together, including the mirrored orientations.
          final manuallyRotated = await service.editPhoto(
            original,
            sideBySide
                ? const PhotoEdit(
                    left: 0, top: 0, width: 1, height: .5, quarterTurns: 1)
                : const PhotoEdit(
                    left: 0, top: 0, width: .5, height: 1, quarterTurns: 1),
          );
          try {
            for (final sample in [
              (photo: first, red: firstRed,
                size: sideBySide ? (80, 100) : (100, 80)),
              (photo: second, red: !firstRed,
                size: sideBySide ? (80, 100) : (100, 80)),
              (photo: manuallyRotated,
                red: sideBySide ? firstRed : !firstRed,
                size: sideBySide ? (100, 80) : (80, 100)),
            ]) {
              final encoded = await File(sample.photo.path).readAsBytes();
              expect(encoded, orderedEquals(sample.photo.previewBytes),
                  reason: 'ML Kit must receive exactly the previewed crop');
              final center = await _decodedCenter(encoded);
              expect((center.width, center.height), sample.size,
                  reason: 'EXIF $orientation + editor crop dimensions');
              expect(center.red, sample.red,
                  reason: 'EXIF $orientation must select the correct pixels');
            }
          } finally {
            await service.release(first);
            await service.release(second);
            await service.release(manuallyRotated);
          }
          expect(await File(file.path).readAsBytes(), orderedEquals(bytes),
              reason: 'Original EXIF and gallery file stay unchanged');
        } finally {
          await service.release(original);
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
