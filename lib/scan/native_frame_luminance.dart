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


/// Bounded 48x48 probe for camera frames, with a 16x16 fallback for small\n/// frames, of the central 60% of the *visible* camera image.
/// Unlike a full-frame average, bright/dark surroundings cannot mask a label
/// positioned in the guide area. A sparse 16x16 grid can miss thin printed
/// strokes entirely and falsely call a bright care label glare. The denser
/// 2304-pixel probe remains bounded and is sampled only on throttled frames.\n/// Small valid frames retain the original 16x16 behavior; malformed frames\n/// still fail closed.
/// This is a light/contrast hint, NOT focus,
/// OCR confidence, or evidence that a label is present. No pixels are stored.
Uint8List? sampleNativeCenterLuminance({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
  required bool bgra,
}) {
  final grid = width >= 48 && height >= 48 ? 48 : 16;
  final channels = bgra ? 4 : 1;
  if (width < grid || height < grid || width * height > 12000000 ||
      rowStride <= 0 || pixelStride < channels ||
      rowStride < (width - 1) * pixelStride + channels ||
      (height - 1) * rowStride + (width - 1) * pixelStride + channels >
          bytes.length) {
    return null;
  }
  final left = width ~/ 5, top = height ~/ 5;
  final regionWidth = width - 2 * left;
  final regionHeight = height - 2 * top;
  final result = Uint8List(grid * grid);
  for (var y = 0; y < grid; y++) {
    final row = top + ((2 * y + 1) * regionHeight) ~/ (2 * grid);
    for (var x = 0; x < grid; x++) {
      final column = left + ((2 * x + 1) * regionWidth) ~/ (2 * grid);
      final offset = row * rowStride + column * pixelStride;
      result[y * grid + x] = bgra
          ? (bytes[offset] * 0.114 +
              bytes[offset + 1] * 0.587 +
              bytes[offset + 2] * 0.299).round()
          : bytes[offset];
    }
  }
  return result;
}
