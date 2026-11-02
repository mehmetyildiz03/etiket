import 'dart:math' as math;
import 'dart:ui';

import 'live_pair_hints.dart';
import 'native_spatial_pairs.dart';

final _bareNumber = RegExp(r'^(?:100|[1-9][0-9]?)$');

/// Fail-closed filter for already-printed, same-line Android ML Kit pairs.
///
/// ML Kit can return "80% PAMUK" in one block and a rival "KETEN" or "20%"
/// in another block at the *same physical row*. Reading only the first block
/// makes the wrong association look stable over multiple frames. Inspect all
/// observed line boxes before allowing an unverified yellow inline hint.
///
/// This never joins tokens, estimates missing percentages, verifies a section,
/// authorizes green, or retains OCR text/pixels after the call. iOS coordinates
/// are not calibrated here; callers must gate this Android-only path.
List<NativeSpatialPair> nativeUnambiguousInlinePairs({
  required Size imageSize,
  required List<List<NativeOcrLine>> blocks,
}) {
  final width = imageSize.width, height = imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0 ||
      width * height > 48000000 || blocks.length > 128) {
    return const [];
  }
  final lines = <NativeOcrLine>[];
  for (final block in blocks) {
    for (final line in block) {
      if (lines.length >= 256) return const [];
      lines.add(line);
    }
  }

  bool valid(Rect b) =>
      b.left.isFinite && b.top.isFinite &&
      b.right.isFinite && b.bottom.isFinite &&
      b.width > 0 && b.height > 0 &&
      b.left >= 0 && b.top >= 0 &&
      b.right <= width && b.bottom <= height;

  bool potentialRival(String text) {
    final trimmed = text.trim();
    return liveHasPossibleCompositionToken(text) ||
        _bareNumber.hasMatch(trimmed) || trimmed == '%';
  }

  final found = <NativeSpatialPair>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final pairs = livePairsFromLine(line.text);
    if (pairs.isEmpty || !valid(line.box)) continue;
    var ambiguous = false;
    for (var j = 0; j < lines.length; j++) {
      if (j == i || !potentialRival(lines[j].text)) continue;
      final other = lines[j];
      // An unlocated composition token might compete with any visible
      // match; never treat missing geometry as evidence of separation.
      if (!valid(other.box)) {
        ambiguous = true;
        break;
      }
      final a = line.box, b = other.box;
      final overlap = math.min(a.bottom, b.bottom) -
          math.max(a.top, b.top);
      if (overlap < .5 * math.min(a.height, b.height) ||
          (a.center.dy - b.center.dy).abs() >
              .5 * math.max(a.height, b.height)) {
        continue;
      }
      // Two independently complete, nonoverlapping printed pairs may
      // legitimately share a row. An isolated rival cannot claim that.
      if (livePairsFromLine(other.text).isNotEmpty && !a.overlaps(b)) {
        continue;
      }
      final gap = math.max(0.0,
          math.max(a.left - b.right, b.left - a.right));
      if (gap <= math.min(width * .05,
          math.max(a.height, b.height) * 2)) {
        ambiguous = true;
        break;
      }
    }
    if (ambiguous) continue;
    for (final pair in pairs) {
      if (found.length >= 8) return const [];
      found.add(NativeSpatialPair(pair, line.box));
    }
  }
  return List.unmodifiable(found);
}
