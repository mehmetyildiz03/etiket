import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';

final _barePrintedNumber = RegExp(r'^(?:100|[1-9][0-9]?)

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
      width * height > 48000000 || lines.length < 2 || lines.length > 256) {
    return const [];
  }

  final ratios = <(int, String)>[];
  final fibers = <(int, String)>[];
  final bareNumbers = <(int, String)>[];
  final percentGlyphs = <int>[];
  final ignored = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final box = lines[i].box;
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) {
      // Invalid unrelated care instructions must not hide real percentage
      // and fiber tokens on dense labels. An unboxed composition token can
      // compete with the candidate, so its geometry still fails closed.
      if (liveHasPossibleCompositionToken(lines[i].text) ||
          _barePrintedNumber.hasMatch(lines[i].text.trim()) ||
          lines[i].text.trim() == '%') return const [];
      ignored.add(i);
      continue;
    }
    // Complete same-line candidates already have a safer extraction path.
    if (livePairsFromLine(lines[i].text).isNotEmpty) continue;
    final percent = liveIsolatedPercent(lines[i].text);
    final fiber = liveIsolatedFiber(lines[i].text);
    if (percent != null) ratios.add((i, percent));
    if (fiber != null) fibers.add((i, fiber));
    final token = lines[i].text.trim();
    if (_barePrintedNumber.hasMatch(token)) bareNumbers.add((i, token));
    if (token == '%') percentGlyphs.add(i);
  }
  if (fibers.isEmpty ||
      (ratios.isEmpty && (bareNumbers.isEmpty || percentGlyphs.isEmpty)) ||
      ratios.length > 8 || bareNumbers.length > 8 ||
      percentGlyphs.length > 8 || fibers.length > 8) {
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
      if (i == ratioIndex || i == fiberIndex || ignored.contains(i)) continue;
      final other = lines[i].box;
      // Overlapping alternative OCR tokens make the row association ambiguous.
      if (other.overlaps(a) || other.overlaps(b)) return false;
      final verticalOverlap = math.min(other.bottom, math.min(a.bottom, b.bottom)) -
          math.max(other.top, math.max(a.top, b.top));
      if (verticalOverlap > 0 &&
          other.left < right.left && other.right > left.right) {
        return false;
      }
    }
    return true;
  }


  // ML Kit can split a REAL printed '80% PAMUK' into '80', '%', 'PAMUK'
  // within one block. Require all three independently observed boxes in
  // their printed order; never infer a missing percent glyph. This is only
  // an unverified yellow camera hint, not an accepted composition.
  bool printedSplitAdjacent(int numberIndex, int glyphIndex, int fiberIndex) {
    final n = lines[numberIndex].box;
    final g = lines[glyphIndex].box;
    final f = lines[fiberIndex].box;
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
        f.left - g.right > math.min(width * .10,
            math.max(n.height, f.height) * 3)) return false;
    for (var i = 0; i < lines.length; i++) {
      if (i == numberIndex || i == glyphIndex || i == fiberIndex ||
          ignored.contains(i)) continue;
      final other = lines[i].box;
      if (other.overlaps(n) || other.overlaps(g) || other.overlaps(f)) {
        return false;
      }
      final rowOverlap = math.min(other.bottom, math.min(n.bottom, f.bottom)) -
          math.max(other.top, math.max(n.top, f.top));
      if (rowOverlap > 0 && other.left < f.left &&
          other.right > n.right) return false;
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
  final usedGlyphs = <int>{}, usedFibers = <int>{};
  for (final (numberIndex, number) in bareNumbers) {
    final matches = <(int, int, String)>[];
    for (final glyphIndex in percentGlyphs) {
      for (final (fiberIndex, fiber) in fibers) {
        if (printedSplitAdjacent(numberIndex, glyphIndex, fiberIndex)) {
          matches.add((glyphIndex, fiberIndex, fiber));
        }
      }
    }
    if (matches.length > 1) return const []; // Competing glyph/fiber.
    if (matches.isEmpty) continue;
    final (glyphIndex, fiberIndex, fiber) = matches.single;
    if (bareNumbers.where((n) =>
        printedSplitAdjacent(n.$1, glyphIndex, fiberIndex)).length != 1 ||
        !usedGlyphs.add(glyphIndex) || !usedFibers.add(fiberIndex)) {
      return const []; // Competing number or reused printed token.
    }
    final value = '$number% $fiber';
    if (!usedValues.add(value)) return const []; // Duplicate row ambiguity.
    results.add(NativeSpatialPair(value,
        lines[numberIndex].box.expandToInclude(lines[glyphIndex].box)
            .expandToInclude(lines[fiberIndex].box)));
  }
  return List.unmodifiable(results);
}
);

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
      width * height > 48000000 || lines.length < 2 || lines.length > 256) {
    return const [];
  }

  final ratios = <(int, String)>[];
  final fibers = <(int, String)>[];
  final ignored = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final box = lines[i].box;
    if (!box.left.isFinite || !box.top.isFinite ||
        !box.right.isFinite || !box.bottom.isFinite ||
        box.width <= 0 || box.height <= 0 ||
        box.left < 0 || box.top < 0 ||
        box.right > width || box.bottom > height) {
      // Invalid unrelated care instructions must not hide real percentage
      // and fiber tokens on dense labels. An unboxed composition token can
      // compete with the candidate, so its geometry still fails closed.
      if (liveHasPossibleCompositionToken(lines[i].text)) return const [];
      ignored.add(i);
      continue;
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
      if (i == ratioIndex || i == fiberIndex || ignored.contains(i)) continue;
      final other = lines[i].box;
      // Overlapping alternative OCR tokens make the row association ambiguous.
      if (other.overlaps(a) || other.overlaps(b)) return false;
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
