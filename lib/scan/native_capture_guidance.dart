import 'dart:typed_data';

import 'photo_scan.dart';

/// Advisory only: measure a bounded local RGBA decode, never the OCR text.
/// The input remains unchanged and no image/EXIF/metrics are persisted.
PhotoCaptureHint? nativeCaptureHintFromRgba(
  Uint8List rgba,
  int width,
  int height,
) {
  // The native validator decodes at most a 720px long edge. Reject unexpected
  // inputs instead of allowing unbounded diagnostic allocations.
  if (width < 16 ||
      height < 16 ||
      width > 720 ||
      height > 720 ||
      rgba.lengthInBytes != width * height * 4) {
    return null;
  }
  const maxSampleEdge = 256;
  final sampleWidth = width > maxSampleEdge ? maxSampleEdge : width;
  final sampleHeight = height > maxSampleEdge ? maxSampleEdge : height;
  final luminance = Uint8List(sampleWidth * sampleHeight);
  var sum = 0;
  var minValue = 255;
  var maxValue = 0;
  for (var y = 0; y < sampleHeight; y++) {
    final sourceY = (y * height) ~/ sampleHeight;
    for (var x = 0; x < sampleWidth; x++) {
      final sourceX = (x * width) ~/ sampleWidth;
      final offset = (sourceY * width + sourceX) * 4;
      final value = (0.299 * rgba[offset] +
              0.587 * rgba[offset + 1] +
              0.114 * rgba[offset + 2])
          .round();
      luminance[y * sampleWidth + x] = value;
      sum += value;
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
  }
  var edgeSum = 0;
  var edgeCount = 0;
  for (var y = 1; y < sampleHeight - 1; y++) {
    for (var x = 1; x < sampleWidth - 1; x++) {
      final i = y * sampleWidth + x;
      final laplacian = 4 * luminance[i] -
          luminance[i - 1] -
          luminance[i + 1] -
          luminance[i - sampleWidth] -
          luminance[i + sampleWidth];
      edgeSum += laplacian.abs();
      edgeCount++;
    }
  }
  final mean = sum / luminance.length;
  final range = maxValue - minValue;
  final edges = edgeSum / edgeCount;
  // Same conservative conditions as web/doku_capture_guidance.js. They
  // describe nearly featureless frames, not a calibrated blur/OCR score.
  if (range <= 16 && edges <= 3 && mean <= 32) {
    return PhotoCaptureHint.veryDark;
  }
  if (range <= 16 && edges <= 3 && mean >= 232) {
    return PhotoCaptureHint.veryBright;
  }
  if (range <= 12 && edges <= 2) {
    return PhotoCaptureHint.lowDetail;
  }
  return null;
}
