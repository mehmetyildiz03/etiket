import 'dart:math' as math;
import 'dart:typed_data';

/// Sample the actual visible pixels, never row padding or chroma bytes.
/// Returns null on malformed camera frames; does not retain source pixels.
Uint8List? sampleNativeLuminance({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
  required bool bgra,
}) {
  final channels = bgra ? 4 : 1;
  if (width <= 0 || height <= 0 || width * height > 12000000 ||
      rowStride <= 0 || pixelStride < channels ||
      rowStride < (width - 1) * pixelStride + channels ||
      (height - 1) * rowStride + (width - 1) * pixelStride + channels >
          bytes.length) {
    return null;
  }
  final pixels = width * height;
  final count = math.min(512, pixels);
  final result = Uint8List(count);
  for (var i = 0; i < count; i++) {
    final pixel = count == 1 ? 0 : (i * (pixels - 1)) ~/ (count - 1);
    final row = pixel ~/ width;
    final column = pixel % width;
    final offset = row * rowStride + column * pixelStride;
    result[i] = bgra
        ? (bytes[offset] * 0.114 +
            bytes[offset + 1] * 0.587 +
            bytes[offset + 2] * 0.299).round()
        : bytes[offset];
  }
  return result;
}
