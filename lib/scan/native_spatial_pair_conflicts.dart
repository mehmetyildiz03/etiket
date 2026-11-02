import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';

final _bareNumber = RegExp(r'^(?:100|[1-9][0-9]?)$');

/// Global ambiguity check for Android ML Kit's split lines INSIDE a block.
///
/// The existing same-block matcher can correctly join "80%" and "PAMUK",
/// but another block may contain "KETEN", "20%" or an intervening word on
/// that same physical row. A locally valid match is not globally unique.
/// Only transient, unverified yellow candidates are returned. No OCR pixels,
/// raw text, EXIF or user edits are stored, and this cannot authorize green.
List<NativeSpatialPair> nativeUnambiguousSpatialPairs({
  required Size imageSize,
  required List<List<NativeOcrLine>> blocks,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || blocks.length > 128) {
    return const [];
  }
  var totalLines = 0;
  for (final block in blocks) {
    totalLines += block.length;
    if (totalLines > 256) return const [];
  }

  bool valid(Rect box) =>
      box.left.isFinite && box.top.isFinite &&
      box.right.isFinite && box.bottom.isFinite &&
      box.width > 0 && box.height > 0 &&
      box.left >= 0 && box.top >= 0 &&
      box.right <= width && box.bottom <= height;

  bool possibleRival(String text) {
    final token = text.trim();
    return liveHasPossibleCompositionToken(text) ||
        _bareNumber.hasMatch(token) || token == '%';
  }

  final result = <NativeSpatialPair>[];
  final seen = <String>{};
  for (var source = 0; source < blocks.length; source++) {
    final candidates = nativeSpatialPairs(
        imageSize: imageSize, lines: blocks[source]);
    for (final candidate in candidates) {
      if (!valid(candidate.box)) continue;
      var ambiguous = false;
      for (var otherBlock = 0; otherBlock < blocks.length && !ambiguous;
          otherBlock++) {
        if (otherBlock == source) continue;
        for (final line in blocks[otherBlock]) {
          final rival = possibleRival(line.text);
          if (!valid(line.box)) {
            // Unlocated competing text could occupy this exact row.
            if (rival) { ambiguous = true; break; }
            continue;
          }
          final a = candidate.box, b = line.box;
          // Even ordinary care text between the split percentage and fiber
          // makes the joined row unsafe.
          if (a.overlaps(b)) { ambiguous = true; break; }
          if (!rival) continue;
          final overlap = math.min(a.bottom, b.bottom) -
              math.max(a.top, b.top);
          if (overlap < .5 * math.min(a.height, b.height) ||
              (a.center.dy - b.center.dy).abs() >
                  .5 * math.max(a.height, b.height)) {
            continue;
          }
          // Two separately complete, non-overlapping printed rows may be
          // side-by-side; an isolated ratio/fiber/glyph cannot claim that.
          if (livePairsFromLine(line.text).isNotEmpty) continue;
          final gap = math.max(0.0,
              math.max(a.left - b.right, b.left - a.right));
          if (gap <= math.min(width * .05,
              math.max(a.height, b.height) * 2)) {
            ambiguous = true;
            break;
          }
        }
      }
      if (ambiguous) continue;
      // Repeated identical printed values in different rows are not a
      // unique spatial observation and must not increase frame stability.
      if (!seen.add(candidate.value)) return const [];
      if (result.length >= 8) return const [];
      result.add(candidate);
    }
  }
  return List.unmodifiable(result);
}
