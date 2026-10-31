import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_spatial_pairs.dart';

void main() {
  const size = Size(1080, 1920);
  const ratio = NativeOcrLine('80%', Rect.fromLTWH(100, 500, 80, 40));
  const fiber = NativeOcrLine('PAMUK', Rect.fromLTWH(210, 502, 160, 40));

  test('literal split tokens in one horizontal row are yellow candidates', () {
    final found = nativeSpatialPairs(imageSize: size, lines: [ratio, fiber]);
    expect(found.map((p) => p.value), ['80% pamuk']);
    expect(found.single.box, const Rect.fromLTRB(100, 500, 370, 542));
    expect(nativeSpatialPairs(imageSize: size, lines: [
      const NativeOcrLine('KETEN', Rect.fromLTWH(100, 600, 120, 40)),
      const NativeOcrLine('%20', Rect.fromLTWH(240, 600, 80, 40)),
    ]).map((p) => p.value), ['20% keten']);
  });

  test('two separated rows keep their own exact printed tokens', () {
    final found = nativeSpatialPairs(imageSize: size, lines: [
      ratio, fiber,
      const NativeOcrLine('20%', Rect.fromLTWH(100, 610, 80, 40)),
      const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
    ]);
    expect(found.map((p) => p.value), ['80% pamuk', '20% polyester']);
  });

  test('stacked lines, distant columns and cross-block tokens never pair', () {
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio,
      const NativeOcrLine('PAMUK', Rect.fromLTWH(100, 550, 160, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio,
      const NativeOcrLine('PAMUK', Rect.fromLTWH(500, 500, 160, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [ratio]), isEmpty);
  });

  test('competing fiber, competing percentage or intervening text fail closed', () {
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, fiber,
      const NativeOcrLine('KETEN', Rect.fromLTWH(220, 502, 150, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, fiber,
      const NativeOcrLine('20%', Rect.fromLTWH(90, 500, 90, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, fiber,
      const NativeOcrLine('OTHER', Rect.fromLTWH(183, 500, 24, 40)),
    ]), isEmpty);
  });

  test('nonliteral tokens and malformed ratios cannot invent candidates', () {
    for (final bad in ['120%', '0%', '1000%', '80', '80% 20%']) {
      expect(nativeSpatialPairs(imageSize: size, lines: [
        NativeOcrLine(bad, ratio.box), fiber,
      ]), isEmpty, reason: bad);
    }
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, const NativeOcrLine('WASH PAMUK', Rect.fromLTWH(210, 502, 160, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      const NativeOcrLine('100%', Rect.fromLTWH(100, 500, 80, 40)),
      fiber,
    ]).single.value, '100% pamuk');
  });

  test('dense Android OCR blocks preserve late real split pairs', () {
    final care = List.generate(75, (i) => NativeOcrLine(
      'WASH AT 30 C $i', Rect.fromLTWH(10, 10 + i * 5.0, 120, 4)));
    final found = nativeSpatialPairs(imageSize: size,
      lines: [...care, ratio, fiber]);
    expect(found.map((p) => p.value), ['80% pamuk']);
    expect(found.single.box, const Rect.fromLTRB(100, 500, 370, 542));
    // Bounded work: oversized blocks must not silently bypass the limit.
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ...List.generate(255, (i) => NativeOcrLine('CARE $i',
        Rect.fromLTWH(10, 10 + i * 5.0, 120, 4))),
      ratio, fiber,
    ]), isEmpty);
  });

  test('unboxed care instructions are ignored but competing tokens block pairing', () {
    const bad = Rect.fromLTWH(-2, 450, 100, 30);
    for (final care in ['WASH AT 30 C', 'IRON LOW']) {
      final found = nativeSpatialPairs(imageSize: size, lines: [
        ratio, fiber, NativeOcrLine(care, bad),
      ]);
      expect(found.map((p) => p.value), ['80% pamuk'], reason: care);
    }
    for (final competing in ['20%', 'KETEN', 'WASH PAMUK',
      '80% KETEN', 'POLYESTER 20%']) {
      expect(nativeSpatialPairs(imageSize: size, lines: [
        ratio, fiber, NativeOcrLine(competing, bad),
      ]), isEmpty, reason: competing);
    }
  });

  test('bad geometry or duplicate same-value rows fail closed', () {
    expect(nativeSpatialPairs(imageSize: Size.zero, lines: [ratio, fiber]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, const NativeOcrLine('PAMUK', Rect.fromLTWH(-1, 500, 100, 40)),
    ]), isEmpty);
    expect(nativeSpatialPairs(imageSize: size, lines: [
      ratio, fiber,
      const NativeOcrLine('80%', Rect.fromLTWH(100, 610, 80, 40)),
      const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 612, 160, 40)),
    ]), isEmpty);
  });
}
