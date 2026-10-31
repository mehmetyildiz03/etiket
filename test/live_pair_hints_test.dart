import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/live_pair_hints.dart';

void main() {
  test('literal same-line percentage and fiber are retained', () {
    expect(livePairsFromLine('80% PAMUK 20% KETEN'),
        ['80% pamuk', '20% keten']);
    expect(livePairsFromLine('PAMUK 80% KETEN 20%'),
        ['80% pamuk', '20% keten']);
    expect(livePairsFromLine('%100 POLYESTER'), ['100% polyester']);
    expect(livePairsFromLine('viskon %40'), ['40% viskon']);
  });
  test('mixed-order same-line native OCR retains both literal pairs', () {
    expect(livePairsFromLine('80% PAMUK KETEN 20%'),
        ['80% pamuk', '20% keten']);
    expect(livePairsFromLine('KETEN 20% 80% PAMUK'),
        ['20% keten', '80% pamuk']);
    expect(livePairsFromLine('70% COTTON LINEN 30%'),
        ['70% cotton', '30% linen']);
  });

  test('shared percentage or fiber without a unique assignment fails closed', () {
    expect(livePairsFromLine('PAMUK 80% KETEN'), isEmpty);
    expect(livePairsFromLine('80% PAMUK 20%'), isEmpty);
    expect(livePairsFromLine('80% PAMUK 20% KETEN'),
        ['80% pamuk', '20% keten']);
    expect(livePairsFromLine('PAMUK 80% KETEN 20%'),
        ['80% pamuk', '20% keten']);
  });

  test('separate lines, missing percent and care instructions are never paired', () {
    expect(livePairsFromLine('80%'), isEmpty);
    expect(livePairsFromLine('PAMUK'), isEmpty);
    expect(livePairsFromLine('30% wash only'), isEmpty);
    expect(livePairsFromLine('PAMUK %'), isEmpty);
  });
  test('malformed and truncated ratios cannot become invented pairs', () {
    for (final text in ['120% PAMUK', '1000% KETEN', 'PAMUK 120%',
      'KETEN 1000%', '0% PAMUK', '101% YÜN', '100% PAMUKLU']) {
      expect(livePairsFromLine(text), isEmpty, reason: text);
    }
  });
  test('native camera flags only plausible missing printed percent for focus', () {
    for (final line in [
      '80 PAMUK', 'KETEN 20', '100 POLYESTER',
      '80% PAMUK 20 KETEN', 'COTTON 70 LINEN 30%',
    ]) {
      expect(liveMissingPercentNearFiber(line), true, reason: line);
    }
    for (final line in [
      '80% PAMUK', '%80 PAMUK', 'KETEN 20%', 'KETEN 20 %',
      'KETEN %20', '0 PAMUK', 'PAMUK 0', '120 KETEN',
      'KETEN 120', '80% PAMUK 20% KETEN', 'PAMUK',
      '30% wash only', 'PAMUKLU 80', '80 PAMUKLU',
    ]) {
      expect(liveMissingPercentNearFiber(line), false, reason: line);
    }
    // The advisory must never create a literal candidate or accepted value.
    expect(livePairsFromLine('80 PAMUK 20 KETEN'), isEmpty);
  });

  test('repeated candidates are deduplicated and never imply approval', () {
    expect(livePairsFromLine('50% PAMUK 50% PAMUK'), ['50% pamuk']);
  });
}
