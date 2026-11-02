import 'dart:typed_data';

/// Freeze one camera-plugin byte buffer before asynchronous ML Kit OCR.
///
/// Camera plugins may recycle their frame buffers while OCR is pending. A
/// transient independent copy makes the OCR bytes belong to the same sampled
/// frame as the exposure snapshot and the tracked boxes. This is not a
/// correctness/approval signal and must never be persisted or uploaded.
///
/// Reject malformed geometry and excessively large allocations. Android
/// single-plane NV21 must be tightly packed; three-plane YUV is converted by
/// yuv420ToNv21 before reaching this helper.
Uint8List? snapshotNativeOcrBytes({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required bool bgra,
}) {
  if (width <= 0 || height <= 0 || width * height > 12000000 ||
      rowStride <= 0 || bytes.length > 48 * 1024 * 1024) {
    return null;
  }
  if (bgra) {
    final rowBytes = width * 4;
    if (rowStride < rowBytes ||
        (height - 1) * rowStride + rowBytes > bytes.length) {
      return null;
    }
  } else {
    // ML Kit's NV21 bridge requires complete, contiguous Y + interleaved VU.
    if (width.isOdd || height.isOdd || rowStride != width ||
        width * height * 3 ~/ 2 > bytes.length) {
      return null;
    }
  }
  return Uint8List.fromList(bytes);
}
