import 'dart:typed_data';

/// Freeze the actual Y (luminance) pixels of one Android camera frame.
///
/// CameraX can expose padded or pixel-strided Y planes. Keeping that padding
/// wastes memory and may reject an otherwise usable frame solely because the
/// source stride is large. Return tightly packed width * height bytes instead.
/// The caller MUST sample with rowStride: width and pixelStride: 1.
///
/// This is ephemeral exposure evidence for the SAME frame as asynchronous
/// OCR, not evidence of recognized text, full label coverage or approval.
/// Never persist, log or upload these bytes. Invalid geometry fails closed.
/// At most 12 million luminance bytes are allocated per sampled frame.
Uint8List? snapshotNativeLumaPlane({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
}) {
  if (width <= 0 || height <= 0 || width * height > 12000000 ||
      rowStride <= 0 || pixelStride <= 0 ||
      rowStride < (width - 1) * pixelStride + 1) {
    return null;
  }
  final needed = (height - 1) * rowStride +
      (width - 1) * pixelStride + 1;
  if (needed > bytes.length) return null;

  final frozen = Uint8List(width * height);
  if (pixelStride == 1 && rowStride == width) {
    frozen.setRange(0, frozen.length, bytes);
  } else if (pixelStride == 1) {
    for (var row = 0; row < height; row++) {
      final start = row * width;
      frozen.setRange(start, start + width, bytes, row * rowStride);
    }
  } else {
    for (var row = 0; row < height; row++) {
      final source = row * rowStride;
      final destination = row * width;
      for (var column = 0; column < width; column++) {
        frozen[destination + column] =
            bytes[source + column * pixelStride];
      }
    }
  }
  return frozen;
}
