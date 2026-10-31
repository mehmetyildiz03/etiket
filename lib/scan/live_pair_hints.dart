/// Conservative same-line, literal percentage+fiber candidates for the
/// native preview. No section inference, no missing ratio completion, no
/// confidence/green status, and no raw OCR text is retained.
const _fibers = 'pamuk|cotton|keten|linen|polyester|poliester|viskon|'
    'viskoz|viscose|elastan|elastane|spandex|yün|yun|wool|poliamid|'
    'polyamide|nylon|naylon|akrilik|acrylic|ipek|silk|modal|liyosel|lyocell';
const _letters = 'a-zA-ZğüşıöçĞÜŞİÖÇ';
final _fiber = RegExp('(?:^|[^$_letters])(?:$_fibers)(?![$_letters])',
    caseSensitive: false);
final _percent = RegExp(r'(?:%\s*\d{1,4}|\d{1,4}\s*%)');
final _ratioFirst = RegExp(
    r'(?:^|[^0-9A-Za-z])(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)\s*('
    '$_fibers' r')(?![a-zA-ZğüşıöçĞÜŞİÖÇ])',
    caseSensitive: false);
final _fiberFirst = RegExp(
    r'(?:^|[^a-zA-ZğüşıöçĞÜŞİÖÇ])(' '$_fibers'
    r')\s*(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)(?![0-9])',
    caseSensitive: false);


final _isolatedRatio = RegExp(
    r'^\s*(?:%\s*(100|[1-9]?[0-9])|(100|[1-9]?[0-9])\s*%)\s*$');
final _isolatedFiber = RegExp(
    r'^\s*(' '$_fibers' r')\s*$', caseSensitive: false);

/// Standalone printed tokens only; no OCR repair or percentage completion.
String? liveIsolatedPercent(String text) {
  final match = _isolatedRatio.firstMatch(text);
  final value = int.tryParse(match?.group(1) ?? match?.group(2) ?? '');
  return value != null && value > 0 && value <= 100 ? '$value' : null;
}

String? liveIsolatedFiber(String text) =>
    _isolatedFiber.firstMatch(text)?.group(1)?.toLowerCase();

/// A missing/invalid OCR box containing a possible composition token can
/// compete with a nearby split pair. Never silently ignore that ambiguity.
/// No inferred values or text are returned by this conservative check.
bool liveHasPossibleCompositionToken(String text) =>
    _percent.hasMatch(text) || _fiber.hasMatch(text);

/// Keep only a unique maximum set of non-overlapping *printed* pairs.
/// Mixed token order is common on real labels (80% PAMUK KETEN 20%).
/// Ambiguous shared tokens fail closed rather than assigning a percentage to
/// the wrong fiber. This is a yellow preview candidate, never approval.
List<String> livePairsFromLine(String text) {
  if (text.length > 512 || !_percent.hasMatch(text) || !_fiber.hasMatch(text)) {
    return const [];
  }
  final candidates = <({int start, int end, String value})>[];

  void collect(RegExp pattern, bool ratioFirst) {
    for (final match in pattern.allMatches(text)) {
      final percent = int.tryParse(ratioFirst
          ? (match.group(1) ?? match.group(2) ?? '')
          : (match.group(2) ?? match.group(3) ?? ''));
      final fiber = match.group(ratioFirst ? 3 : 1)?.toLowerCase();
      if (percent == null || percent < 1 || percent > 100 || fiber == null) {
        continue;
      }
      candidates.add((start: match.start, end: match.end,
          value: '$percent% $fiber'));
    }
  }

  collect(_ratioFirst, true);
  collect(_fiberFirst, false);
  if (candidates.isEmpty || candidates.length > 32) return const [];
  candidates.sort((a, b) {
    final byEnd = a.end.compareTo(b.end);
    return byEnd != 0 ? byEnd : a.start.compareTo(b.start);
  });

  // Weighted interval scheduling: maximize complete pairs, not regex order.
  // Count optimal solutions up to two. Ties are genuinely ambiguous, so
  // return no pairs rather than guessing which shared token belongs where.
  final count = candidates.length;
  final scores = List<int>.filled(count + 1, 0);
  final ways = List<int>.filled(count + 1, 1);
  final previous = List<int>.filled(count + 1, 0);
  final taken = List<bool>.filled(count + 1, false);
  for (var i = 1; i <= count; i++) {
    final current = candidates[i - 1];
    var compatible = i - 1;
    while (compatible > 0 &&
        candidates[compatible - 1].end > current.start) {
      compatible--;
    }
    final withCurrent = scores[compatible] + 1;
    final withoutCurrent = scores[i - 1];
    if (withCurrent > withoutCurrent) {
      scores[i] = withCurrent;
      ways[i] = ways[compatible];
      previous[i] = compatible;
      taken[i] = true;
    } else if (withCurrent < withoutCurrent) {
      scores[i] = withoutCurrent;
      ways[i] = ways[i - 1];
      previous[i] = i - 1;
    } else {
      scores[i] = withCurrent;
      ways[i] = 2;
    }
  }
  if (ways[count] != 1 || scores[count] > 8) return const [];
  final selected = <({int start, int end, String value})>[];
  var i = count;
  while (i > 0) {
    if (taken[i]) selected.add(candidates[i - 1]);
    i = previous[i];
  }
  selected.sort((a, b) => a.start.compareTo(b.start));
  final result = <String>[];
  for (final candidate in selected) {
    if (!result.contains(candidate.value)) result.add(candidate.value);
  }
  return List.unmodifiable(result);
}
