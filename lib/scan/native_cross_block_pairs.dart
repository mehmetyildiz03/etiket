import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';

/// Conservatively recovers *printed* percentage/fiber tokens that ML Kit
/// places in separate single-line text blocks on the same physical row.
///
/// Unlike same-block recovery, cross-block matching requires isolated tokens,
/// a narrow horizontal gap, strong row alignment, and global one-to-one
/// geometry. A competing or unboxed composition token fails closed.
/// Results are transient YELLOW hints only: never approval, green readiness,
/// an inferred percentage, or a substitute for full-resolution photo OCR.
List<NativeSpatialPair> nativeCrossBlockPairs({
  required Size imageSize,
  required List<List<NativeOcrLine>> blocks,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || blocks.length < 2 || blocks.length > 128) {
    return const [];
  }

  bool valid(Rect b) =>
      b.left.isFinite && b.top.isFinite &&
      b.right.isFinite && b.bottom.isFinite &&
      b.width > 0 && b.height > 0 &&
      b.left >= 0 && b.top >= 0 &&
      b.right <= width && b.bottom <= height;

  // ML Kit also groups vertical percentage and fiber columns into separate
  // MULTI-line blocks. Recover their printed rows only if each block is a
  // homogeneous, vertically separated column of isolated literal tokens.
  // Mixed text, overlapping rows and drifting column origins are ambiguous.
  bool isolatedColumn(List<NativeOcrLine> lines) {
    if (lines.length < 2 || lines.length > 8) return false;
    final allRatios =
        lines.every((line) => liveIsolatedPercent(line.text) != null);
    final allFibers =
        lines.every((line) => liveIsolatedFiber(line.text) != null);
    if (!allRatios && !allFibers) return false;
    final ordered = [...lines]
      ..sort((a, b) => a.box.top.compareTo(b.box.top));
    final left = ordered.first.box.left;
    for (var i = 0; i < ordered.length; i++) {
      final box = ordered[i].box;
      if (!valid(box) || (box.left - left).abs() > width * .025 ||
          (i > 0 && box.top < ordered[i - 1].box.bottom)) {
        return false;
      }
    }
    return true;
  }

  // Keep the pre-existing one-line recovery when a separate multi-line
  // column is incomplete. Otherwise adding column support could hide a
  // previously visible, independently unambiguous single-line pair.
  List<NativeSpatialPair> singleLineFallback() {
    final singleBlocks = blocks.where((block) => block.length == 1).toList();
    if (singleBlocks.length < 2) return const [];
    return nativeCrossBlockPairs(
        imageSize: imageSize, blocks: singleBlocks);
  }

  var hasMultiLineColumn = false;
  final entries = <({int block, NativeOcrLine line, bool eligible})>[];
  var scannedLines = 0;
  for (var block = 0; block < blocks.length; block++) {
    final lines = blocks[block];
    final eligible = lines.length == 1 || isolatedColumn(lines);
    if (lines.length > 1 && eligible) hasMultiLineColumn = true;
    for (final line in lines) {
      if (++scannedLines > 256) return const [];
      if (!valid(line.box)) {
        // Unknown geometry of a possible competing composition token cannot
        // be silently ignored when pairing two other blocks.
        if (liveHasPossibleCompositionToken(line.text)) return const [];
        continue;
      }
      entries.add((block: block, line: line, eligible: eligible));
    }
  }

  final ratios = <(int, String)>[];
  final fibers = <(int, String)>[];
  for (var i = 0; i < entries.length; i++) {
    if (!entries[i].eligible) continue;
    final text = entries[i].line.text;
    final ratio = liveIsolatedPercent(text);
    final fiber = liveIsolatedFiber(text);
    if (ratio != null) ratios.add((i, ratio));
    if (fiber != null) fibers.add((i, fiber));
  }
  if (ratios.isEmpty || fibers.isEmpty) return const [];
  if (ratios.length > 8 || fibers.length > 8) {
    return hasMultiLineColumn ? singleLineFallback() : const [];
  }
  if (hasMultiLineColumn && ratios.length != fibers.length) {
    return singleLineFallback();
  }

  bool adjacent(int ratioIndex, int fiberIndex) {
    if (entries[ratioIndex].block == entries[fiberIndex].block) return false;
    final a = entries[ratioIndex].line.box;
    final b = entries[fiberIndex].line.box;
    final left = a.left < b.left ? a : b;
    final right = a.left < b.left ? b : a;
    if (left.right >= right.left) return false;
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlap < .75 * math.min(a.height, b.height) ||
        (a.center.dy - b.center.dy).abs() >
            .25 * math.max(a.height, b.height)) {
      return false;
    }
    final gap = right.left - left.right;
    if (gap > math.min(width * .04, math.max(a.height, b.height) * 2)) {
      return false;
    }
    // Another OCR token between or overlapping either candidate may change
    // the association, even when it is not a recognized textile word.
    for (var i = 0; i < entries.length; i++) {
      if (i == ratioIndex || i == fiberIndex) continue;
      final other = entries[i].line.box;
      if (other.overlaps(a) || other.overlaps(b)) return false;
      final rowOverlap =
          math.min(other.bottom, math.min(a.bottom, b.bottom)) -
          math.max(other.top, math.max(a.top, b.top));
      if (rowOverlap > 0 &&
          other.left < right.left && other.right > left.right) {
        return false;
      }
    }
    return true;
  }

  final found = <NativeSpatialPair>[];
  final seen = <String>{};
  for (final (ratioIndex, percent) in ratios) {
    final matches = fibers.where((f) => adjacent(ratioIndex, f.$1)).toList();
    if (matches.length > 1) return const []; // Competing fibers.
    if (matches.isEmpty) continue;
    final (fiberIndex, fiber) = matches.single;
    if (ratios.where((r) => adjacent(r.$1, fiberIndex)).length != 1) {
      return const []; // Competing ratios.
    }
    final value = '$percent% $fiber';
    if (!seen.add(value)) return const []; // Duplicate composition row.
    found.add(NativeSpatialPair(value,
        entries[ratioIndex].line.box.expandToInclude(entries[fiberIndex].line.box)));
  }
  // For column layouts, a missing/extra row must not be silently paired
  // with another section. Keep partial columns yellow without inventing data.
  if (hasMultiLineColumn && found.length != ratios.length) {
    return singleLineFallback();
  }
  return List.unmodifiable(found);
}
