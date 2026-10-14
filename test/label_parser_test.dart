import 'package:etiket/domain/label_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts TR/EN names and common unambiguous abbreviations', () {
    const aliases = {
      'Pamuk': ['pamuk', 'PAMUK', 'cotton', 'CO'],
      'Polyester': ['polyester', 'poliester', 'PES', 'PET', 'PL'],
      'Keten': ['keten', 'linen', 'LI'],
      'Viskon': ['viskon', 'viskoz', 'viscose', 'CV', 'VI'],
      'Modal': ['modal', 'CMD'],
      'Liyosel': ['liyosel', 'lyocell', 'CLY'],
      'Yün': ['yün', 'YÜN', 'yun', 'wool', 'WO'],
      'İpek': ['ipek', 'İPEK', 'silk', 'SE'],
      'Poliamid': ['poliamid', 'polyamide', 'nylon', 'naylon', 'PA'],
      'Elastan': ['elastan', 'elastane', 'spandex', 'EL', 'EA'],
      'Akrilik': ['akrilik', 'acrylic', 'PAN', 'PC'],
      'Asetat': ['asetat', 'acetate', 'CA'],
      'Kaşmir': ['kaşmir', 'cashmere', 'WS'],
      'Bambu viskon': ['bambu viskon', 'bamboo viscose'],
    };
    for (final entry in aliases.entries) {
      for (final alias in entry.value) {
        final parsed = parseLabel('100% $alias');
        expect(parsed.isValid, isTrue, reason: alias);
        expect(parsed.sections.single.fibers.single.name, entry.key);
      }
    }
  });

  test('accepts prefix/suffix, multiline, mixed and decimal percentages', () {
    const inputs = [
      '70% cotton 30% polyester',
      'cotton 70 %\npolyester 30 %',
      '% 70 pamuk; polyester %30',
      'CO70% / PES30%',
      'cotton 70 pct | polyester 30 percent',
      'yüzde 70 pamuk\nyüzde 30 polyester',
      '70,50% cotton, 29.50% polyester',
      '７０', // Unsupported digits must stay unresolved, never become a valid label.
    ];
    for (final input in inputs.take(inputs.length - 1)) {
      final parsed = parseLabel(input);
      expect(parsed.isValid, isTrue, reason: input);
      expect(parsed.sections.single.total, 100, reason: input);
    }
    expect(parseLabel(inputs.last).isValid, isFalse);
    final decimal = parseLabel('70,5％ pamuk 29.5% polyester');
    expect(decimal.isValid, isTrue);
    expect(decimal.sections.single.fibers.map((fiber) => fiber.percent), [70.5, 29.5]);
  });

  test('keeps outer fabric, lining, filling and repeated headings separate', () {
    const raw = 'Dış kumaş: 60% CO 35% PES 5% EL\n'
        'LINING: VI 100%\nDolgu: 100% polyester\nShell: cotton 100%';
    final parsed = parseLabel(raw);
    expect(parsed.rawText, raw);
    expect(parsed.isValid, isTrue);
    expect(parsed.sections.map((section) => section.name),
        ['Dış kumaş', 'Astar', 'Dolgu', 'Dış kumaş']);
    expect(parsed.sections.map((section) => section.id).toSet(), hasLength(4));
    expect(parsed.sections.first.fibers.map((fiber) => fiber.name),
        ['Pamuk', 'Polyester', 'Elastan']);
    expect(parsed.sections.last.fibers.single.name, 'Pamuk');
  });

  test('accepts standalone and inline known headings', () {
    for (final input in [
      'Outer fabric\n70% cotton 30% polyester\nLining\n100% viscose',
      'Shell: 100% CO Lining: 100% CO',
      'Dış kumaş 100% pamuk; Astar 100% viskon',
      'DIŞ KUMAŞ: 100% CO\nASTAR: 100% VI',
      'Shell 1: 100% CO\nShell 2: 100% PES',
    ]) {
      final parsed = parseLabel(input);
      expect(parsed.isValid, isTrue, reason: input);
      expect(parsed.sections, hasLength(2));
    }
  });

  test('compact prefix percentages keep material acronyms intact', () {
    for (final text in ['%100LI', '%100linen', '%100lyocell', '%100ipek']) {
      expect(parseLabel(text).isValid, isTrue, reason: text);
      expect(parseLabel(text).sections.single.fibers.single.percent, 100);
    }
  });

  test('percentages in separate sections cannot compensate for each other', () {
    final parsed = parseLabel('Shell: CO 90%\nLining: 60% VI 50% PES');
    expect(parsed.isValid, isFalse);
    expect(parsed.sections.map((section) => section.total), [90, 110]);
    expect(parsed.sections.every((section) => section.issues.any(
      (issue) => issue.code == LabelIssueCode.invalidTotal,
    )), isTrue);
  });

  test('unknown material and ambiguous abbreviations are not guessed', () {
    for (final name in ['mystery fiber', 'P', 'PE', 'rayon', 'bamboo', 'Tencel']) {
      final parsed = parseLabel('100% $name');
      expect(parsed.isValid, isFalse, reason: name);
      expect(parsed.sections.single.fibers.single.name, isNull, reason: name);
      expect(parsed.sections.single.fibers.single.rawName, name);
    }
  });

  test('missing ratios stay missing and are not filled to 100', () {
    final parsed = parseLabel('70% cotton\npolyester');
    expect(parsed.isValid, isFalse);
    expect(parsed.sections.single.fibers.map((fiber) => fiber.percent), [70, null]);
    expect(parsed.sections.single.fibers.last.issues.any(
      (issue) => issue.code == LabelIssueCode.missingPercentage,
    ), isTrue);
    expect(parseLabel('cotton 70 polyester 30').isValid, isFalse);
  });

  test('OCR-like, malformed and out of range percentages are not repaired', () {
    for (final amount in ['7O%', '1O0%', '70..5%', '70.555%', '%70%', '100%%', '-10%', '101%', '0%']) {
      final parsed = parseLabel('$amount cotton');
      expect(parsed.isValid, isFalse, reason: amount);
      expect(parsed.sections.single.fibers.any((fiber) => fiber.percent == null),
          isTrue, reason: amount);
    }
  });

  test('conflicts and multiple matches do not become valid compositions', () {
    for (final input in [
      '70% cotton polyester',
      'cotton 70% 30%',
      '50% cotton 50% CO',
      '100% cotton\n100% cotton',
      '70% cotton 30% polyester\nMade in Turkey',
      '100% cotton / wool',
    ]) {
      expect(parseLabel(input).isValid, isFalse, reason: input);
    }
    expect(parseLabel('Shell: 100% CO\nLining: 100% CO').isValid, isTrue);
  });

  test('unknown headings and empty sections require review', () {
    final unknown = parseLabel('Pocket: 100% cotton');
    expect(unknown.isValid, isFalse);
    expect(unknown.sections.single.name, 'Pocket');
    expect(unknown.sections.single.issues.first.code, LabelIssueCode.unknownSection);
    expect(parseLabel('Shell:\nLining: 100% cotton').isValid, isFalse);
  });

  test('raw fragments and stable source ids preserve evidence without mutation', () {
    const raw = 'Shell: 70% CO; 30% mystery fiber\r\nLining: 100% VI';
    final first = parseLabel(raw);
    final second = parseLabel(raw);
    expect(first.rawText, raw);
    expect(first.sections.first.fibers.first.rawText, '70% CO');
    expect(first.sections.first.fibers.last.rawText, '30% mystery fiber');
    expect(first.sections.first.fibers.map((fiber) => fiber.id),
        second.sections.first.fibers.map((fiber) => fiber.id));
    expect(() => first.sections.clear(), throwsUnsupportedError);
    expect(() => first.sections.first.fibers.clear(), throwsUnsupportedError);
  });

  test('empty and overly long input return explicit issues', () {
    expect(parseLabel(' \n ').issues.single.code, LabelIssueCode.emptyInput);
    final longText = '100% cotton\n' * 2000;
    final parsed = parseLabel(longText);
    expect(parsed.rawText, longText);
    expect(parsed.isValid, isFalse);
    expect(parsed.issues.single.code, LabelIssueCode.inputTooLong);
  });

  test('a long malformed numeric run is retained without guessing', () {
    final numeric = '1' * 19000;
    final parsed = parseLabel(numeric);
    expect(parsed.isValid, isFalse);
    expect(parsed.sections.single.fibers.single.rawText, numeric);
    expect(parsed.sections.single.fibers.single.percent, isNull);
  });
}
