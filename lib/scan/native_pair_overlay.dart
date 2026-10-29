import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Only draw provisional native OCR boxes when the camera preview and OCR
/// coordinates are in the same known portrait orientation. This is not a
/// correctness signal; uncalibrated iOS, landscape and mirrored previews
/// deliberately have no overlay.
bool canShowNativePairOverlay({
  required bool android,
  required bool rearCamera,
  required bool portraitUp,
  required int? rotationDegrees,
  required Size? previewSize,
  required Size? ocrImageSize,
  required Map<String, Rect>? normalizedBoxes,
  required int stableFrames,
}) {
  if (!android || !rearCamera || !portraitUp || rotationDegrees != 90 ||
      stableFrames < 2 || previewSize == null ||
      !previewSize.width.isFinite || !previewSize.height.isFinite ||
      previewSize.width <= 0 || previewSize.height <= 0 ||
      previewSize.width < previewSize.height ||
      ocrImageSize == null ||
      !ocrImageSize.width.isFinite || !ocrImageSize.height.isFinite ||
      ocrImageSize.width <= 0 || ocrImageSize.height <= 0 ||
      (ocrImageSize.width / ocrImageSize.height -
          previewSize.height / previewSize.width).abs() > .02 ||
      normalizedBoxes == null || normalizedBoxes.isEmpty ||
      normalizedBoxes.length > 8) {
    return false;
  }
  for (final entry in normalizedBoxes.entries) {
    final b = entry.value;
    if (entry.key.isEmpty || !b.left.isFinite || !b.top.isFinite ||
        !b.right.isFinite || !b.bottom.isFinite ||
        b.width <= 0 || b.height <= 0 || b.left < 0 || b.top < 0 ||
        b.right > 1 || b.bottom > 1) {
      return false;
    }
  }
  return true;
}

/// Amber outlines are a location hint for literal percentage+fiber OCR lines,
/// never a green readiness/approval indicator. Nothing is stored or uploaded.
class NativePairOverlay extends StatelessWidget {
  const NativePairOverlay({super.key, required this.normalizedBoxes});

  final Map<String, Rect> normalizedBoxes;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sarı: tahmini yüzde ve elyaf satırları. Doğrulanmadı.',
    child: IgnorePointer(
      child: CustomPaint(
        painter: _PairBoxPainter(normalizedBoxes),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _PairBoxPainter extends CustomPainter {
  const _PairBoxPainter(this.boxes);
  final Map<String, Rect> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final outline = Paint()
      ..color = const Color(0xFFFFC247)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = const Color(0x33FFC247)
      ..style = PaintingStyle.fill;
    for (final b in boxes.values) {
      final rect = Rect.fromLTRB(b.left * size.width, b.top * size.height,
          b.right * size.width, b.bottom * size.height);
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(rounded, fill);
      canvas.drawRRect(rounded, outline);
    }
  }

  @override
  bool shouldRepaint(covariant _PairBoxPainter oldDelegate) =>
      !mapEquals(oldDelegate.boxes, boxes);
}
