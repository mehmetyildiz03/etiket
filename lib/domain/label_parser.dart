import 'fabric.dart';

/// Parsing produces proposals, never verified garment data.
enum LabelIssueCode {
  emptyInput, inputTooLong, unknownMaterial, ambiguousMaterial, missingMaterial,
  missingPercentage, malformedPercentage, outOfRangePercentage, duplicateMaterial,
  invalidTotal, unknownSection, emptySection,
}

class LabelIssue {
  final LabelIssueCode code;
  final String message;
  const LabelIssue(this.code, this.message);
}

class ParsedFiber {
  final String id;
  final String rawText;
  final String rawName;
  final String rawPercentage;
  final String? name;
  final num? percent;
  final List<LabelIssue> issues;

  ParsedFiber({
    required this.id, required this.rawText, required this.rawName,
    required this.rawPercentage, required this.name, required this.percent,
    required Iterable<LabelIssue> issues,
  }) : issues = List.unmodifiable(issues);
}

class ParsedSection {
  final String id;
  final String name;
  final String rawHeading;
  final List<ParsedFiber> fibers;
  final List<LabelIssue> issues;

  ParsedSection({
    required this.id, required this.name, required this.rawHeading,
    required Iterable<ParsedFiber> fibers, required Iterable<LabelIssue> issues,
  }) : fibers = List.unmodifiable(fibers), issues = List.unmodifiable(issues);

  num get total => fibers.fold<num>(0, (sum, fiber) => sum + (fiber.percent ?? 0));
  bool get isValid => fibers.isNotEmpty && issues.isEmpty &&
      fibers.every((fiber) => fiber.issues.isEmpty);
}

class ParsedLabel {
  final String rawText;
  final List<ParsedSection> sections;
  final List<LabelIssue> issues;
  ParsedLabel(this.rawText, Iterable<ParsedSection> sections, Iterable<LabelIssue> issues)
      : sections = List.unmodifiable(sections), issues = List.unmodifiable(issues);
  bool get isValid => sections.isNotEmpty && issues.isEmpty &&
      sections.every((section) => section.isValid);
}

String _foldCase(String value) => value.replaceAll('İ', 'i').toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ç', 'c').replaceAll('ğ', 'g').replaceAll('ö', 'o')
    .replaceAll('ş', 's').replaceAll('ü', 'u');

String _normalize(String value) =>
    _foldCase(value).replaceAll(RegExp(r'\s+'), ' ').trim();

const _materials = <String, String>{
  'pamuk': 'Pamuk', 'cotton': 'Pamuk', 'co': 'Pamuk',
  'polyester': 'Polyester', 'poliester': 'Polyester', 'pes': 'Polyester', 'pet': 'Polyester', 'pl': 'Polyester',
  'keten': 'Keten', 'linen': 'Keten', 'li': 'Keten',
  'viskon': 'Viskon', 'viskoz': 'Viskon', 'viscose': 'Viskon', 'cv': 'Viskon', 'vi': 'Viskon',
  'modal': 'Modal', 'cmd': 'Modal',
  'liyosel': 'Liyosel', 'lyocell': 'Liyosel', 'cly': 'Liyosel',
  'yun': 'Yün', 'wool': 'Yün', 'wo': 'Yün',
  'ipek': 'İpek', 'silk': 'İpek', 'se': 'İpek',
  'poliamid': 'Poliamid', 'polyamide': 'Poliamid', 'nylon': 'Poliamid', 'naylon': 'Poliamid', 'pa': 'Poliamid',
  'elastan': 'Elastan', 'elastane': 'Elastan', 'spandex': 'Elastan', 'el': 'Elastan', 'ea': 'Elastan',
  'akrilik': 'Akrilik', 'acrylic': 'Akrilik', 'pan': 'Akrilik', 'pc': 'Akrilik',
  'asetat': 'Asetat', 'acetate': 'Asetat', 'ca': 'Asetat',
  'kasmir': 'Kaşmir', 'cashmere': 'Kaşmir', 'ws': 'Kaşmir',
  'bambu viskon': 'Bambu viskon', 'bamboo viscose': 'Bambu viskon',
};
const _ambiguousMaterials = {'p', 'c', 'pe', 'rayon', 'bamboo', 'bambu', 'tencel'};
const _headings = <String, String>{
  'dış kumaş': 'Dış kumaş', 'dis kumas': 'Dış kumaş',
  'outer fabric': 'Dış kumaş', 'shell': 'Dış kumaş', 'outer': 'Dış kumaş',
  'astar': 'Astar', 'lining': 'Astar',
  'dolgu': 'Dolgu', 'filling': 'Dolgu', 'padding': 'Dolgu',
  'ana kumaş': 'Ana kumaş', 'ana kumas': 'Ana kumaş', 'main fabric': 'Ana kumaş',
  'composition': 'Ana kumaş', 'bileşim': 'Ana kumaş', 'bilesim': 'Ana kumaş',
};

class _Heading {
  final int start;
  final int end;
  final String raw;
  final String name;
  final bool known;
  const _Heading(this.start, this.end, this.raw, this.name, this.known);
}

enum _TokenKind { name, percentage, separator }
class _Token {
  final _TokenKind kind;
  final int start;
  final int end;
  final String raw;
  final String? name;
  final num? percent;
  final String numericText;
  final LabelIssue? issue;
  const _Token(this.kind, this.start, this.end, this.raw,
      {this.name, this.percent, this.numericText = '', this.issue});
}

/// Exact matching only. No OCR substitutions, ratio completion or fuzzy aliases.
ParsedLabel parseLabel(String raw) {
  if (raw.trim().isEmpty) {
    return ParsedLabel(raw, [], [
      const LabelIssue(LabelIssueCode.emptyInput,
          'Etiket metni boş. Metni yapıştırın veya elle giriş yapın.'),
    ]);
  }
  if (raw.length > 20000) {
    return ParsedLabel(raw, [], [
      const LabelIssue(LabelIssueCode.inputTooLong,
          'Metin çok uzun. En fazla 20.000 karakterlik etiket metni girin.'),
    ]);
  }
  final headings = _findHeadings(raw);
  final sections = <ParsedSection>[];
  if (headings.isEmpty) {
    sections.add(_parseSection(raw, 0, raw.length, 'Ana kumaş', '', true));
  } else {
    final first = headings.first.start;
    if (raw.substring(0, first).replaceAll(RegExp(r'[\s;|,]'), '').isNotEmpty) {
      sections.add(_parseSection(raw, 0, first, 'Ana kumaş', '', true));
    }
    for (var i = 0; i < headings.length; i++) {
      final h = headings[i];
      final end = i + 1 < headings.length ? headings[i + 1].start : raw.length;
      sections.add(_parseSection(raw, h.end, end, h.name, h.raw, h.known));
    }
  }
  return ParsedLabel(raw, sections, []);
}

List<_Heading> _findHeadings(String raw) {
  final aliases = _headings.keys.map(_normalize).toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final known = RegExp(
    r'(^|[\s;|])(' '${aliases.map(RegExp.escape).join('|')}'
        r')(?:([ \t]+\d+)?[ \t]*:|[ \t]*(?=\r?\n|$)|[ \t]+(?=[%％]?\s*\d))',
    caseSensitive: false, multiLine: true,
  );
  final result = <_Heading>[];
  for (final match in known.allMatches(_foldCase(raw))) {
    final alias = match.group(2)!;
    final canonical = _headings.entries.firstWhere(
      (entry) => _normalize(entry.key) == _normalize(alias),
    ).value;
    final suffix = (match.group(3) ?? '').trim();
    final start = match.start + match.group(1)!.length;
    result.add(_Heading(start, match.end, raw.substring(start, match.end).trim(),
        suffix.isEmpty ? canonical : '$canonical $suffix', true));
  }
  final other = RegExp(r'(^|[\n;|])\s*([A-Za-zÇĞİÖŞÜçğıöşü][A-Za-zÇĞİÖŞÜçğıöşü 0-9_-]{0,60}):');
  for (final match in other.allMatches(raw)) {
    final name = match.group(2)!.trim();
    if (_materials.containsKey(_normalize(name))) {
      continue; // "Cotton: 70%" is a fiber, not a section heading.
    }
    final start = match.start + match.group(1)!.length;
    if (result.any((h) => start <= h.start && match.end >= h.end)) {
      continue;
    }
    result.add(_Heading(start, match.end, name, name, false));
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

ParsedSection _parseSection(
    String raw, int start, int end, String name, String heading, bool known) {
  final tokens = _tokenize(raw, start, end);
  final fibers = <ParsedFiber>[];
  var i = 0;
  while (i < tokens.length) {
    final token = tokens[i];
    if (token.kind == _TokenKind.separator) {
      i++;
      continue;
    }
    _Token? material = token.kind == _TokenKind.name ? token : null;
    _Token? percentage = token.kind == _TokenKind.percentage ? token : null;
    if (i + 1 < tokens.length) {
      final next = tokens[i + 1];
      if (token.kind == _TokenKind.name && next.kind == _TokenKind.percentage) {
        percentage = next;
        i++;
      } else if (token.kind == _TokenKind.percentage && next.kind == _TokenKind.name) {
        material = next;
        i++;
      }
    }
    final from = material == null ? percentage!.start
        : percentage == null ? material.start
        : material.start < percentage.start ? material.start : percentage.start;
    final to = material == null ? percentage!.end
        : percentage == null ? material.end
        : material.end > percentage.end ? material.end : percentage.end;
    fibers.add(ParsedFiber(
      id: 'fiber-$from-$to',
      rawText: raw.substring(from, to).trim(), rawName: material?.raw ?? '',
      rawPercentage: percentage?.numericText ?? '',
      name: material?.name, percent: percentage?.percent,
      issues: [
        if (material == null)
          const LabelIssue(LabelIssueCode.missingMaterial, 'Elyaf adı eksik; elle seçin.'),
        if (percentage == null)
          const LabelIssue(LabelIssueCode.missingPercentage, 'Yüzde eksik; kalan oran otomatik doldurulmadı.'),
        ...<LabelIssue?>[material?.issue, percentage?.issue].whereType<LabelIssue>(),
      ],
    ));
    i++;
  }
  final issues = <LabelIssue>[];
  if (!known) {
    issues.add(const LabelIssue(LabelIssueCode.unknownSection,
        'Bölüm başlığı tanınmadı; bölüm adını kontrol edip düzenleyin.'));
  }
  if (fibers.isEmpty) {
    issues.add(const LabelIssue(LabelIssueCode.emptySection,
        'Bu bölümde elyaf ve yüzde bulunamadı.'));
  }
  final names = fibers.map((fiber) => fiber.name).whereType<String>().toList();
  if (names.toSet().length != names.length) {
    issues.add(const LabelIssue(LabelIssueCode.duplicateMaterial,
        'Aynı elyaf bu bölümde birden fazla kez geçiyor; satırları kontrol edin.'));
  }
  if (fibers.isNotEmpty &&
      (fibers.any((fiber) => fiber.percent == null) ||
       fibers.fold<int>(0, (sum, fiber) => sum + (percentageUnits(fiber.percent ?? 0) ?? 0)) != 10000)) {
    issues.add(const LabelIssue(LabelIssueCode.invalidTotal,
        'Her kumaş bölümünün toplamı ayrı ayrı %100 olmalı; eksik oran tamamlanmadı.'));
  }
  return ParsedSection(id: 'section-$start', name: name,
      rawHeading: heading, fibers: fibers, issues: issues);
}

List<_Token> _tokenize(String raw, int start, int end) {
  final content = raw.substring(start, end);
  final aliases = _materials.keys.map(RegExp.escape).join('|');
  final percentages = RegExp(
    // A compact prefix such as "%100LI" must not swallow the fiber acronym
    // as OCR-like digits. Only an exact known alias supplies this boundary.
    r'[%％]\s*[+-]?\d{1,20}(?:[.,]\d{1,2})?(?=(?:' '$aliases' r')\b)'
    r'|'
    r'[%％]\s*[+-]?[0-9OoIl?][0-9OoIl?.,]{0,20}\s*[%％]*'
    r'|[+-]?[0-9][0-9OoIl?.,]{0,20}\s*(?:[%％]+|pct\b|percent\b)'
    r'|y[uü]zde\s+[+-]?[0-9OoIl?][0-9OoIl?.,]{0,20}',
    caseSensitive: false,
  );
  final result = <_Token>[];
  var offset = 0;
  for (final match in percentages.allMatches(content)) {
    result.addAll(_names(raw, start + offset, start + match.start));
    final text = match.group(0)!;
    final numeric = RegExp(r'[+-]?[0-9OoIl?][0-9OoIl?.,]*').firstMatch(text)!.group(0)!;
    final value = parsePercentage(numeric);
    LabelIssue? issue;
    final signCount = RegExp('[%％]').allMatches(text).length;
    if (signCount > 1 || !RegExp(r'^[+-]?\d+(?:[.,]\d{1,2})?$').hasMatch(numeric)) {
      issue = const LabelIssue(LabelIssueCode.malformedPercentage,
          'Yüzde okunamadı; harfler veya bozuk sayılar otomatik düzeltilmedi.');
    } else if (value == null) {
      issue = const LabelIssue(LabelIssueCode.outOfRangePercentage,
          'Yüzde 0’dan büyük ve en fazla 100 olmalı.');
    }
    result.add(_Token(_TokenKind.percentage, start + match.start, start + match.end,
        text, percent: issue == null ? value : null, numericText: numeric, issue: issue));
    offset = match.end;
  }
  result.addAll(_names(raw, start + offset, end));
  return result;
}

List<_Token> _names(String raw, int start, int end) {
  final result = <_Token>[];
  final pieces = RegExp(r'[^,;|/]+|[,;|/]').allMatches(raw.substring(start, end));
  for (final piece in pieces) {
    final text = piece.group(0)!;
    if (RegExp(r'^[,;|/]$').hasMatch(text)) {
      result.add(_Token(_TokenKind.separator, start + piece.start, start + piece.end, text));
      continue;
    }
    final words = RegExp(r'[^\s:]+').allMatches(text).toList();
    var i = 0;
    while (i < words.length) {
      final word = words[i];
      String? canonical;
      var count = 1;
      if (i + 1 < words.length) {
        canonical = _materials[_normalize('${word.group(0)} ${words[i + 1].group(0)}')];
        if (canonical != null) {
          count = 2;
        }
      }
      canonical ??= _materials[_normalize(word.group(0)!)];
      if (canonical == null) {
        while (i + count < words.length) {
          final next = words[i + count].group(0)!;
          final two = i + count + 1 < words.length
              ? '$next ${words[i + count + 1].group(0)}' : next;
          if (_materials.containsKey(_normalize(next)) || _materials.containsKey(_normalize(two))) {
            break;
          }
          count++;
        }
      }
      final from = start + piece.start + word.start;
      final to = start + piece.start + words[i + count - 1].end;
      final original = raw.substring(from, to);
      final ambiguous = _ambiguousMaterials.contains(_normalize(original));
      result.add(_Token(_TokenKind.name, from, to, original, name: canonical,
          issue: canonical != null ? null : LabelIssue(
            ambiguous ? LabelIssueCode.ambiguousMaterial : LabelIssueCode.unknownMaterial,
            ambiguous ? 'Elyaf adı veya kısaltması belirsiz; elle seçin.'
                : 'Elyaf tanınmadı; bilinen bir elyafa otomatik eşlenmedi.',
          )));
      i += count;
    }
  }
  return result;
}
