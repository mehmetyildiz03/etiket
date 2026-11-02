import 'dart:typed_data';

/// Freeze only the Y (luminance) pixels of one sampled Android camera frame.
///
/// ML Kit OCR is asynchronous: camera-plugin buffers must not be assumed to
/// remain unchanged until its bounding boxes arrive. ROI exposure guidance
/// must inspect the SAME frame as the OCR request, not a recycled later frame.
///
/// Bounded to 12 MP and 16 MiB, with no persistence, logging or upload.
/// A malformed/oversized plane returns null so advice stays unverified.
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
  if (needed > 16 * 1024 * 1024 || needed > bytes.length) return null;
  final frozen = Uint8List(needed);
  frozen.setRange(0, needed, bytes);
  return frozen;
}
