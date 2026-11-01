import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';

final _bareRatio = RegExp(r'^\s*(?:100|[1-9][0-9]?)\s*$');

/// Advisory ONLY: ML Kit sometimes puts a bare number and a fiber in
/// different OCR lines within one block. If they occupy one unambiguous row,
/// request closer focus to check for a tiny missed '%' glyph. This NEVER
/// creates a percentage-fiber pair, changes OCR text, or enables green.
bool nativeSplitMissingPercentHint({
  required Size imageSize,
  required List<NativeOcrLine> lines,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || lines.length < 2 || lines.length > 256) {
    return false;
  }

  bool valid(Rect b) =>
      b.left.isFinite && b.top.isFinite &&
      b.right.isFinite && b.bottom.isFinite &&
      b.width > 0 && b.height > 0 &&
      b.left >= 0 && b.top >= 0 &&
      b.right <= width && b.bottom <= height;

  final bare = <int>[], fibers = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isBare = _bareRatio.hasMatch(line.text);
    final isFiber = liveIsolatedFiber(line.text) != null;
    if (!valid(line.box)) {
      // A missing box on a competing composition token is ambiguous.
      if (isBare || isFiber || liveHasPossibleCompositionToken(line.text)) {
        return false;
      }
      continue;
    }
    if (isBare) bare.add(i);
    if (isFiber) fibers.add(i);
  }
  if (bare.isEmpty || fibers.isEmpty ||
      bare.length > 8 || fibers.length > 8) return false;

  bool adjacent(int numberIndex, int fiberIndex) {
    final a = lines[numberIndex].box, b = lines[fiberIndex].box;
    final left = a.left < b.left ? a : b;
    final right = a.left < b.left ? b : a;
    if (left.right >= right.left) return false;
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlap < .65 * math.min(a.height, b.height) ||
        (a.center.dy - b.center.dy).abs() >
            .35 * math.max(a.height, b.height)) return false;
    final gap = right.left - left.right;
    if (gap > math.min(width * .10, math.max(a.height, b.height) * 3)) {
      return false;
    }
    // A '%' or other visible token between them may be part of the ratio.
    // Do not claim the percent sign is missing in that case.
    for (var i = 0; i < lines.length; i++) {
      if (i == numberIndex || i == fiberIndex) continue;
      final other = lines[i].box;
      if (!valid(other)) continue;
      if (other.overlaps(a) || other.overlaps(b)) return false;
      final rowOverlap = math.min(other.bottom, math.min(a.bottom, b.bottom)) -
          math.max(other.top, math.max(a.top, b.top));
      if (rowOverlap > 0 &&
          other.left < right.left && other.right > left.right) return false;
    }
    return true;
  }

  for (final numberIndex in bare) {
    final matchingFibers = fibers.where((i) => adjacent(numberIndex, i)).toList();
    if (matchingFibers.length != 1) continue;
    final fiberIndex = matchingFibers.single;
    if (bare.where((i) => adjacent(i, fiberIndex)).length == 1) return true;
  }
  return false;
}
