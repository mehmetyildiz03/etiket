import 'dart:ui';

/// Geometry-only camera hints for OCR lines with an explicit percentage+fiber
/// pair. Never infers a missing fiber, percentage, label section or approval.
enum NativeFramingHint { unknown, moveBack, moveCloser, steady }

class NativePairGeometry {
  const NativePairGeometry(this.center, this.hint);
  final Offset? center; // Normalized OCR image coordinates, not screen pixels.
  final NativeFramingHint hint;
}

/// Boxes and dimensions must be in the SAME (possibly rotated) OCR space.
/// Reject partially outside/malformed boxes rather than giving false advice.
NativePairGeometry assessNativePairGeometry({
  required Size imageSize,
  required List<Rect> pairLineBoxes,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || pairLineBoxes.isEmpty) {
    return const NativePairGeometry(null, NativeFramingHint.unknown);
  }
  for (final box in pairLineBoxes) {
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) {
      return const NativePairGeometry(null, NativeFramingHint.unknown);
    }
  }
  var x = 0.0, y = 0.0, tallest = 0.0;
  var nearEdge = false;
  for (final box in pairLineBoxes) {
    x += box.center.dx / width;
    y += box.center.dy / height;
    if (box.height > tallest) tallest = box.height;
    if (box.left / width < .045 || box.right / width > .955 ||
        box.top / height < .045 || box.bottom / height > .955) {
      nearEdge = true;
    }
  }
  final center = Offset(x / pairLineBoxes.length, y / pairLineBoxes.length);
  // An edge-clipped label is more urgent than enlarging small text.
  final hint = nearEdge ? NativeFramingHint.moveBack
      : tallest / height < .018 ? NativeFramingHint.moveCloser
      : NativeFramingHint.steady;
  return NativePairGeometry(center, hint);
}

/// The same immutable orientation snapshot must drive ML Kit input metadata
/// and subsequent OCR-box geometry. No screen-space mapping is assumed.
Size? nativeOcrImageSize({
  required int width,
  required int height,
  required int rotationDegrees,
  required bool android,
}) {
  if (width <= 0 || height <= 0 || width * height > 48000000 ||
      !const [0, 90, 180, 270].contains(rotationDegrees)) {
    return null;
  }
  final swap = android && (rotationDegrees == 90 || rotationDegrees == 270);
  return Size((swap ? height : width).toDouble(),
      (swap ? width : height).toDouble());
}

 
/// Conservative frame-to-frame agreement for actual OCR percentage+fiber
/// line boxes. All coordinates are normalized in the SAME OCR image space.
/// Duplicate or malformed pairs fail closed: this never authorizes green.
Map<String, Rect>? normalizeNativePairBoxes({
  required Size imageSize,
  required Map<String, Rect> pairBoxes,
  bool duplicatePair = false,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (duplicatePair || pairBoxes.isEmpty || pairBoxes.length > 8 ||
      !width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000) return null;
  final normalized = <String, Rect>{};
  for (final entry in pairBoxes.entries) {
    final box = entry.value;
    if (entry.key.isEmpty || !box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 || box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) return null;
    normalized[entry.key] = Rect.fromLTRB(
      box.left / width, box.top / height,
      box.right / width, box.bottom / height);
  }
  return Map.unmodifiable(normalized);
}

/// A matching text fingerprint alone is insufficient: individual lines must
/// stay in roughly the same location and size across independent frames.
/// This is a conservative UI hint only, never an OCR correctness score.
bool nativePairBoxesAgree(Map<String, Rect>? previous,
    Map<String, Rect>? current) {
  if (previous == null || current == null || previous.isEmpty ||
      previous.length != current.length) return false;
  for (final entry in current.entries) {
    final before = previous[entry.key], after = entry.value;
    if (before == null || !_normalizedRectValid(before) ||
        !_normalizedRectValid(after)) return false;
    if ((before.center - after.center).distance > .06) return false;
    final widthRatio = before.width / after.width;
    final heightRatio = before.height / after.height;
    if (widthRatio < .67 || widthRatio > 1.5 ||
        heightRatio < .67 || heightRatio > 1.5) return false;
    final overlap = before.intersect(after);
    if (overlap.width <= 0 || overlap.height <= 0) return false;
    final intersection = overlap.width * overlap.height;
    final union = before.width * before.height +
        after.width * after.height - intersection;
    if (union <= 0 || intersection / union < .35) return false;
  }
  return true;
}

bool _normalizedRectValid(Rect box) =>
    box.left.isFinite && box.top.isFinite &&
    box.right.isFinite && box.bottom.isFinite &&
    box.width > 0 && box.height > 0 &&
    box.left >= 0 && box.top >= 0 && box.right <= 1 && box.bottom <= 1;
