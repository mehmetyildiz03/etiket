import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';

final _barePrintedNumber = RegExp(r'^(?:100|[1-9][0-9]?)$');

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
        if (liveHasPossibleCompositionToken(line.text) ||
            _barePrintedNumber.hasMatch(line.text.trim()) ||
            line.text.trim() == '%') {
          return const [];
        }
        continue;
      }
      entries.add((block: block, line: line, eligible: eligible));
    }
  }

  final ratios = <(int, String)>[];
  final fibers = <(int, String)>[];
  final bareNumbers = <(int, String)>[];
  final percentGlyphs = <int>[];
  for (var i = 0; i < entries.length; i++) {
    if (!entries[i].eligible) continue;
    final text = entries[i].line.text;
    final ratio = liveIsolatedPercent(text);
    final fiber = liveIsolatedFiber(text);
    if (ratio != null) ratios.add((i, ratio));
    if (fiber != null) fibers.add((i, fiber));
    // Split glyphs may be paired only from distinct, isolated one-line blocks.
    // Mixed/multiline blocks are too ambiguous for three-way recovery.
    if (blocks[entries[i].block].length == 1) {
      final token = text.trim();
      if (_barePrintedNumber.hasMatch(token)) bareNumbers.add((i, token));
      if (token == '%') percentGlyphs.add(i);
    }
  }
  if (fibers.isEmpty ||
      (ratios.isEmpty && (bareNumbers.isEmpty || percentGlyphs.isEmpty))) {
    return const [];
  }
  if (ratios.length > 8 || fibers.length > 8 ||
      bareNumbers.length > 8 || percentGlyphs.length > 8) {
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

  // Recover only a REAL printed number + percent glyph + fiber in three
  // separate ML Kit blocks. This remains a transient yellow OCR hint.
  bool splitAdjacent(int numberIndex, int glyphIndex, int fiberIndex) {
    final nBlock = entries[numberIndex].block;
    final gBlock = entries[glyphIndex].block;
    final fBlock = entries[fiberIndex].block;
    if (nBlock == gBlock || nBlock == fBlock || gBlock == fBlock) {
      return false;
    }
    final n = entries[numberIndex].line.box;
    final g = entries[glyphIndex].line.box;
    final f = entries[fiberIndex].line.box;
    if (n.right >= g.left || g.right >= f.left) return false;
    bool sameRow(Rect a, Rect b) {
      final overlap = math.min(a.bottom, b.bottom) -
          math.max(a.top, b.top);
      return overlap >= .65 * math.min(a.height, b.height) &&
          (a.center.dy - b.center.dy).abs() <=
              .45 * math.max(a.height, b.height);
    }
    if (!sameRow(n, g) || !sameRow(g, f) || !sameRow(n, f) ||
        g.left - n.right > math.min(width * .025,
            math.max(n.height, g.height) * .9) ||
        f.left - g.right > math.min(width * .04,
            math.max(n.height, f.height) * 2)) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (i == numberIndex || i == glyphIndex || i == fiberIndex) continue;
      final other = entries[i].line.box;
      if (other.overlaps(n) || other.overlaps(g) || other.overlaps(f)) {
        return false;
      }
      final rowOverlap =
          math.min(other.bottom, math.min(n.bottom, f.bottom)) -
          math.max(other.top, math.max(n.top, f.top));
      if (rowOverlap > 0 && other.left < f.left && other.right > n.right) {
        return false;
      }
    }
    return true;
  }

  final found = <NativeSpatialPair>[];
  final seen = <String>{};
  final usedFibers = <int>{};
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
    usedFibers.add(fiberIndex);
    found.add(NativeSpatialPair(value,
        entries[ratioIndex].line.box.expandToInclude(entries[fiberIndex].line.box)));
  }
  final usedGlyphs = <int>{};
  for (final (numberIndex, number) in bareNumbers) {
    final matches = <(int, int, String)>[];
    for (final glyphIndex in percentGlyphs) {
      for (final (fiberIndex, fiber) in fibers) {
        if (splitAdjacent(numberIndex, glyphIndex, fiberIndex)) {
          matches.add((glyphIndex, fiberIndex, fiber));
        }
      }
    }
    if (matches.length > 1) return const []; // Competing printed tokens.
    if (matches.isEmpty) continue;
    final (glyphIndex, fiberIndex, fiber) = matches.single;
    if (bareNumbers.where((n) =>
            splitAdjacent(n.$1, glyphIndex, fiberIndex)).length != 1 ||
        !usedGlyphs.add(glyphIndex) || !usedFibers.add(fiberIndex)) {
      return const []; // Competing number or reused glyph/fiber.
    }
    final value = '$number% $fiber';
    if (!seen.add(value)) return const []; // Duplicate row.
    found.add(NativeSpatialPair(value,
        entries[numberIndex].line.box
            .expandToInclude(entries[glyphIndex].line.box)
            .expandToInclude(entries[fiberIndex].line.box)));
  }
  // For column layouts, a missing/extra row must not be silently paired
  // with another section. Keep partial columns yellow without inventing data.
  if (hasMultiLineColumn && found.length != ratios.length) {
    return singleLineFallback();
  }
  return List.unmodifiable(found);
}
