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
  test('repeated candidates are deduplicated and never imply approval', () {
    expect(livePairsFromLine('50% PAMUK 50% PAMUK'), ['50% pamuk']);
  });
}
