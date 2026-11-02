import 'dart:typed_data';

/// Freeze only the actual camera pixels before asynchronous ML Kit OCR.
///
/// Camera plugins can recycle their frame buffers while recognition is
/// pending. Android NV21 is already tightly packed; iOS BGRA may include
/// per-row padding which ML Kit must not mistake for visible pixels.
///
/// The result is a new, tightly packed local buffer. The caller MUST pass
/// bytesPerRow = width * 4 for BGRA and width for NV21. Nothing is persisted
/// or uploaded. Invalid geometry fails closed; at most 48 MiB is allocated.
Uint8List? snapshotNativeOcrBytes({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required bool bgra,
}) {
  if (width <= 0 || height <= 0 || width * height > 12000000 ||
      rowStride <= 0 || bytes.length > 64 * 1024 * 1024) {
    return null;
  }

  if (bgra) {
    final rowBytes = width * 4;
    final packedLength = rowBytes * height;
    final needed = (height - 1) * rowStride + rowBytes;
    if (rowStride < rowBytes || needed > bytes.length ||
        packedLength > 48 * 1024 * 1024) {
      return null;
    }
    final frozen = Uint8List(packedLength);
    if (rowStride == rowBytes) {
      frozen.setRange(0, packedLength, bytes);
    } else {
      for (var row = 0; row < height; row++) {
        final target = row * rowBytes;
        frozen.setRange(target, target + rowBytes, bytes, row * rowStride);
      }
    }
    return frozen;
  }

  // ML Kit's NV21 bridge requires complete, contiguous Y + interleaved VU.
  if (width.isOdd || height.isOdd || rowStride != width) return null;
  final needed = width * height * 3 ~/ 2;
  if (needed > bytes.length) return null;
  // Do not copy trailing camera-plugin bytes into the OCR input.
  return Uint8List(needed)..setRange(0, needed, bytes);
}
