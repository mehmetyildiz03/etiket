import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';

/// A transient OCR line in the same ML Kit text block. No text is persisted.
class NativeOcrLine {
  const NativeOcrLine(this.text, this.box);
  final String text;
  final Rect box;
}

/// An explicitly printed percentage and fiber, spatially adjacent on one row.
/// This is an unverified yellow candidate, never a parsed/approved value.
class NativeSpatialPair {
  const NativeSpatialPair(this.value, this.box);
  final String value;
  final Rect box;
}

/// Recover only unambiguous horizontal splits of a printed percentage and
/// fiber inside ONE OCR block. Never join vertically stacked lines, infer a
/// missing token, or cross text blocks (which may represent different sections).
List<NativeSpatialPair> nativeSpatialPairs({
  required Size imageSize,
  required List<NativeOcrLine> lines,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || lines.length < 2 || lines.length > 32) {
    return const [];
  }

  final ratios = <(int, String)>[];
  final fibers = <(int, String)>[];
  for (var i = 0; i < lines.length; i++) {
    final box = lines[i].box;
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) {
      return const []; // Any uncertain geometry invalidates spatial pairing.
    }
    // Complete same-line candidates already have a safer extraction path.
    if (livePairsFromLine(lines[i].text).isNotEmpty) continue;
    final percent = liveIsolatedPercent(lines[i].text);
    final fiber = liveIsolatedFiber(lines[i].text);
    if (percent != null) ratios.add((i, percent));
    if (fiber != null) fibers.add((i, fiber));
  }
  if (ratios.isEmpty || fibers.isEmpty || ratios.length > 8 ||
      fibers.length > 8) {
    return const [];
  }

  bool adjacent(int ratioIndex, int fiberIndex) {
    final a = lines[ratioIndex].box, b = lines[fiberIndex].box;
    final left = a.left < b.left ? a : b;
    final right = a.left < b.left ? b : a;
    if (left.right >= right.left) return false;
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlap < .65 * math.min(a.height, b.height) ||
        (a.center.dy - b.center.dy).abs() > .35 * math.max(a.height, b.height)) {
      return false;
    }
    final gap = right.left - left.right;
    if (gap > math.min(width * .10, math.max(a.height, b.height) * 3)) {
      return false;
    }
    // A third visible token between the two could change the association.
    for (var i = 0; i < lines.length; i++) {
      if (i == ratioIndex || i == fiberIndex) continue;
      final other = lines[i].box;
      final verticalOverlap = math.min(other.bottom, math.min(a.bottom, b.bottom)) -
          math.max(other.top, math.max(a.top, b.top));
      if (verticalOverlap > 0 &&
          other.left < right.left && other.right > left.right) {
        return false;
      }
    }
    return true;
  }

  final results = <NativeSpatialPair>[];
  final usedValues = <String>{};
  for (final (ratioIndex, percent) in ratios) {
    final matches = fibers.where((f) => adjacent(ratioIndex, f.$1)).toList();
    if (matches.length != 1) continue;
    final (fiberIndex, fiber) = matches.single;
    final competing = ratios.where((r) => adjacent(r.$1, fiberIndex)).length;
    if (competing != 1) continue;
    final value = '$percent% $fiber';
    if (!usedValues.add(value)) return const []; // Duplicate is ambiguous.
    results.add(NativeSpatialPair(
      value, lines[ratioIndex].box.expandToInclude(lines[fiberIndex].box)));
  }
  return List.unmodifiable(results);
}
