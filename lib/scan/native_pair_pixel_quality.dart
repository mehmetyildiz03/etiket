import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'live_frame_quality.dart';

/// Samples only the REAL camera pixels underneath an Android ML Kit OCR
/// percentage-fiber line. The box is normalized in the ROTATED OCR image,
/// not the preview widget. All four rotations are mapped back to the source
/// Y plane; unsupported or malformed geometry fails closed.
///
/// This is ephemeral exposure/contrast guidance, never focus confidence,
/// OCR correctness, a verified composition, or evidence of full label coverage.
Uint8List? sampleNativeOcrPairLuminance({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
  required bool bgra,
  required int rotationDegrees,
  required Rect normalizedBox,
}) {
  final channels = bgra ? 4 : 1;
  if (width <= 0 || height <= 0 || width * height > 12000000 ||
      rowStride <= 0 || pixelStride < channels ||
      rowStride < (width - 1) * pixelStride + channels ||
      (height - 1) * rowStride + (width - 1) * pixelStride + channels >
          bytes.length ||
      !const [0, 90, 180, 270].contains(rotationDegrees) ||
      !normalizedBox.left.isFinite || !normalizedBox.top.isFinite ||
      !normalizedBox.right.isFinite || !normalizedBox.bottom.isFinite ||
      normalizedBox.width <= 0 || normalizedBox.height <= 0 ||
      normalizedBox.left < 0 || normalizedBox.top < 0 ||
      normalizedBox.right > 1 || normalizedBox.bottom > 1) {
    return null;
  }

  final swapped = rotationDegrees == 90 || rotationDegrees == 270;
  final ocrWidth = swapped ? height : width;
  final ocrHeight = swapped ? width : height;
  // Include a narrow amount of adjacent label background when comparing
  // dark printed strokes against the paper. Never expand outside the frame.
  final left = math.max(0.0, normalizedBox.left - .004);
  final top = math.max(0.0, normalizedBox.top - .004);
  final right = math.min(1.0, normalizedBox.right + .004);
  final bottom = math.min(1.0, normalizedBox.bottom + .004);
  final gridX = math.min(48, ((right - left) * ocrWidth).floor());
  final gridY = math.min(48, ((bottom - top) * ocrHeight).floor());
  if (gridX < 8 || gridY < 8) return null;

  final samples = Uint8List(gridX * gridY);
  for (var y = 0; y < gridY; y++) {
    final oy = math.min(ocrHeight - 1,
        ((top + (y + .5) * (bottom - top) / gridY) * ocrHeight).floor());
    for (var x = 0; x < gridX; x++) {
      final ox = math.min(ocrWidth - 1,
          ((left + (x + .5) * (right - left) / gridX) * ocrWidth).floor());
      final int rawX, rawY;
      switch (rotationDegrees) {
        case 90:
          rawX = oy;
          rawY = height - 1 - ox;
        case 180:
          rawX = width - 1 - ox;
          rawY = height - 1 - oy;
        case 270:
          rawX = width - 1 - oy;
          rawY = ox;
        default:
          rawX = ox;
          rawY = oy;
      }
      final offset = rawY * rowStride + rawX * pixelStride;
      samples[y * gridX + x] = bgra
          ? (bytes[offset] * .114 + bytes[offset + 1] * .587 +
              bytes[offset + 2] * .299).round()
          : bytes[offset];
    }
  }
  return samples;
}


/// Evaluate every literal, geometrically tracked percentage-fiber OCR line,
/// not only the shortest one. A readable small line must not conceal a
/// washed-out or dark second line elsewhere on the label.
///
/// The first eight lines are bounded by the live overlay matcher. Any invalid
/// ROI fails closed: central scene brightness cannot substitute for pixels
/// from a known printed line. Mixed exposure problems use generic low-detail
/// guidance rather than incorrectly requesting only more/less light.
/// No frame bytes or text are retained; this never authorizes green/approval.
LiveFrameQuality assessNativeMatchedPairQuality({
  required Uint8List bytes,
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
  required bool bgra,
  required int rotationDegrees,
  required Iterable<Rect> normalizedBoxes,
}) {
  var count = 0;
  LiveFrameQuality? problem;
  for (final box in normalizedBoxes) {
    count++;
    if (count > 8) return LiveFrameQuality.unknown;
    final samples = sampleNativeOcrPairLuminance(
      bytes: bytes,
      width: width,
      height: height,
      rowStride: rowStride,
      pixelStride: pixelStride,
      bgra: bgra,
      rotationDegrees: rotationDegrees,
      normalizedBox: box,
    );
    if (samples == null) return LiveFrameQuality.unknown;
    final quality = assessLiveLuminance(samples);
    if (quality == LiveFrameQuality.unknown) return LiveFrameQuality.unknown;
    if (quality == LiveFrameQuality.usable) continue;
    if (problem != null && problem != quality) {
      problem = LiveFrameQuality.lowDetail;
    } else {
      problem = quality;
    }
  }
  if (count == 0) return LiveFrameQuality.unknown;
  return problem ?? LiveFrameQuality.usable;
}
