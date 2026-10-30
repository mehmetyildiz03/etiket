import 'dart:ui';

/// Conservative cue that *visible OCR text* reaches the camera frame edge.
/// This cannot establish full label coverage, and never authorizes green,
/// parsed values or approval. Only transient bounding boxes are inspected.
bool visibleTextTouchesFrameEdge({
  required Size imageSize,
  required List<Rect> textLineBoxes,
  required int matchedPairCount,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (matchedPairCount < 1 || matchedPairCount > 8 ||
      textLineBoxes.length < 2 || textLineBoxes.length > 64 ||
      !width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000) {
    return false;
  }

  var nearEdge = false;
  for (final box in textLineBoxes) {
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) {
      return false; // Unknown geometry must not produce a specific hint.
    }
    if (box.left / width < .04 || box.top / height < .04 ||
        box.right / width > .96 || box.bottom / height > .96) {
      nearEdge = true;
    }
  }
  return nearEdge;
}
