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
final _isolatedFiber = RegExp('^\\s*($_fibers)\\s*$', caseSensitive: false);

/// Standalone printed tokens only; no OCR repair or percentage completion.
String? liveIsolatedPercent(String text) {
  final match = _isolatedRatio.firstMatch(text);
  final value = int.tryParse(match?.group(1) ?? match?.group(2) ?? '');
  return value != null && value > 0 && value <= 100 ? '$value' : null;
}

String? liveIsolatedFiber(String text) =>
    _isolatedFiber.firstMatch(text)?.group(1)?.toLowerCase();

List<String> livePairsFromLine(String text) {
  final firstPercent = _percent.firstMatch(text);
  final firstFiber = _fiber.firstMatch(text);
  if (firstPercent == null || firstFiber == null) return const [];
  final ratioFirst = firstPercent.start <= firstFiber.start;
  final result = <String>[];
  for (final match in (ratioFirst ? _ratioFirst : _fiberFirst).allMatches(text)) {
    final percent = int.tryParse(ratioFirst
        ? (match.group(1) ?? match.group(2) ?? '')
        : (match.group(2) ?? match.group(3) ?? ''));
    final fiber = match.group(ratioFirst ? 3 : 1)?.toLowerCase();
    if (percent == null || percent <= 0 || percent > 100 || fiber == null) continue;
    final value = '$percent% $fiber';
    if (!result.contains(value) && result.length < 8) result.add(value);
  }
  return List.unmodifiable(result);
}
