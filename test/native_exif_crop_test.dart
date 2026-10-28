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
const _syntheticJpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCABkAKADAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDxKvxo/wBKwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgAoAKACgAoA9ur/ABvP9WwoAKACgAoAKACgAoAKACgDxGv9kD/KQKACgAoAKACgAoAKACgAoA9ur/G8/wBWwoAKACgAoAKACgAoAKACgAoAKACgAoA/9k=';

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

  test('D4.2 native EXIF 6/8 crop keeps the intended source pixels', () async {
    final directory = await Directory.current.createTemp('synthetic-exif-');
    try {
      for (final orientation in [6, 8]) {
        final bytes = _jpegWithOrientation(orientation);
        final file = File('${directory.path}/exif-$orientation.jpg');
        await file.writeAsBytes(bytes);
        final service = NativePhotoSource();
        final original = await service.adopt(XFile(file.path));
        try {
          final source = original.sourceImage;
          expect(source, isNotNull);
          // The native editor must show the EXIF-oriented dimensions, not
          // the encoded 160x100 JPEG's unrotated pixel grid.
          expect((source!.width, source.height), (100, 160));
          final top = await service.editPhoto(original,
              const PhotoEdit(left: 0, top: 0, width: 1, height: .5));
          final bottom = await service.editPhoto(original,
              const PhotoEdit(left: 0, top: .5, width: 1, height: .5));
          try {
            for (final sample in [
              (photo: top, red: orientation == 6),
              (photo: bottom, red: orientation == 8),
            ]) {
              final encoded = await File(sample.photo.path).readAsBytes();
              expect(encoded, orderedEquals(sample.photo.previewBytes),
                  reason: 'ML Kit must receive exactly the previewed crop');
              final center = await _decodedCenter(encoded);
              expect((center.width, center.height), (100, 80));
              expect(center.red, sample.red,
                  reason: 'EXIF $orientation must crop the correct half');
            }
          } finally {
            await service.release(top);
            await service.release(bottom);
          }
          expect(await File(file.path).readAsBytes(), orderedEquals(bytes),
              reason: 'Gallery source and its EXIF metadata stay unchanged');
        } finally {
          await service.release(original);
        }
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
