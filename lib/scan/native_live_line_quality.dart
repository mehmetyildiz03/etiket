import 'dart:ui';

/// Merge REAL Android ML Kit line regions for temporary exposure guidance.
/// Matched boxes are already normalized in OCR coordinates; incomplete lines
/// are raw OCR-space rectangles. No text, pixels, or approval is returned.
///
/// A missed printed percent on another line must not be hidden by a clear
/// matched pair. Unknown/malformed geometry fails closed rather than silently
/// measuring only the good line. This is NOT an OCR correctness metric.
List<Rect>? nativeLiveQualityRegions({
  required Size? imageSize,
  required Map<String, Rect>? matchedBoxes,
  required List<Rect> incompleteLineBoxes,
  required bool missingPercent,
}) {
  if (imageSize == null || !imageSize.width.isFinite ||
      !imageSize.height.isFinite || imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      imageSize.width * imageSize.height > 48000000) return null;

  final regions = <Rect>[];
  if (matchedBoxes != null) regions.addAll(matchedBoxes.values);

  if (missingPercent) {
    // A split '%' without usable coordinates is still a reason for a detail
    // retry, but it is NOT evidence that the matched line represents it.
    if (incompleteLineBoxes.isEmpty) return null;
    for (final box in incompleteLineBoxes) {
      if (!box.left.isFinite || !box.top.isFinite ||
          !box.right.isFinite || !box.bottom.isFinite ||
          box.width <= 0 || box.height <= 0 ||
          box.left < 0 || box.top < 0 ||
          box.right > imageSize.width ||
          box.bottom > imageSize.height) return null;
      regions.add(Rect.fromLTRB(
        box.left / imageSize.width, box.top / imageSize.height,
        box.right / imageSize.width, box.bottom / imageSize.height,
      ));
    }
  }

  if (regions.isEmpty || regions.length > 8) return null;
  for (final box in regions) {
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > 1 || box.bottom > 1) return null;
  }
  return List<Rect>.unmodifiable(regions);
}
