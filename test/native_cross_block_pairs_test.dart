import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_cross_block_pairs.dart';
import 'package:etiket/scan/native_spatial_pairs.dart';

void main() {
  const size = Size(1080, 1920);
  const ratio = NativeOcrLine('80%', Rect.fromLTWH(100, 500, 80, 40));
  const fiber = NativeOcrLine('PAMUK', Rect.fromLTWH(210, 502, 160, 40));

  test('literal percentage and fiber in different ML Kit blocks are yellow hints', () {
    final found = nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
    ]);
    expect(found.map((p) => p.value), ['80% pamuk']);
    expect(found.single.box, const Rect.fromLTRB(100, 500, 370, 542));
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [const NativeOcrLine('KETEN', Rect.fromLTWH(100, 600, 120, 40))],
      [const NativeOcrLine('%20', Rect.fromLTWH(240, 602, 80, 40))],
    ]).map((p) => p.value), ['20% keten']);
  });

  test('two independent rows preserve their exact printed percentages', () {
    final found = nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('20%', Rect.fromLTWH(100, 610, 80, 40))],
      [const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40))],
    ]);
    expect(found.map((p) => p.value), ['80% pamuk', '20% polyester']);
  });

  test('same block, missing percent and mixed-content blocks never synthesize', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio, fiber],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [const NativeOcrLine('80', Rect.fromLTWH(100, 500, 80, 40))],
      [fiber],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio, const NativeOcrLine('WASH', Rect.fromLTWH(100, 550, 90, 30))],
      [fiber],
    ]), isEmpty);
  });

  test('cross-section, vertical and distant columns are not matched', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio],
      [const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 560, 160, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio],
      [const NativeOcrLine('PAMUK', Rect.fromLTWH(600, 500, 160, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio],
      [const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 560, 160, 40))],
      [const NativeOcrLine('LINING', Rect.fromLTWH(100, 545, 150, 25))],
    ]), isEmpty);
  });

  test('intervening words and competing OCR tokens fail closed', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('OTHER', Rect.fromLTWH(182, 500, 26, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(215, 502, 155, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('20%', Rect.fromLTWH(102, 502, 78, 40))],
    ]), isEmpty);
  });

  test('unboxed competing composition, duplicates and oversized input fail closed', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('20%', Rect.fromLTWH(-5, 500, 80, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      [const NativeOcrLine('80%', Rect.fromLTWH(100, 610, 80, 40))],
      [const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 612, 160, 40))],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      ...List.generate(129, (i) => [
        NativeOcrLine('CARE', Rect.fromLTWH(10, 10 + i * 8.0, 60, 6)),
      ]),
      [ratio], [fiber],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio], [fiber],
      List.generate(257, (i) => NativeOcrLine(
        'CARE', Rect.fromLTWH(10, 10 + i * 5.0, 60, 4))),
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: Size.zero, blocks: [
      [ratio], [fiber],
    ]), isEmpty);
  });

  test('ML Kit vertical percentage and fiber columns recover both printed rows', () {
    final found = nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('20%', Rect.fromLTWH(100, 610, 80, 40)),
      ],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
    ]);
    expect(found.map((p) => p.value), ['80% pamuk', '20% polyester']);
    expect(found.map((p) => p.box), [
      const Rect.fromLTRB(100, 500, 370, 542),
      const Rect.fromLTRB(100, 610, 410, 652),
    ]);
  });

  test('a column with missing or extra OCR tokens cannot silently pair rows', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('20%', Rect.fromLTWH(100, 610, 80, 40)),
      ],
      [fiber],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [ratio],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
    ]), isEmpty);
  });

  test('mixed, overlapping or misaligned OCR blocks are not composition columns', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('WASH', Rect.fromLTWH(100, 610, 80, 40)),
      ],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('20%', Rect.fromLTWH(100, 520, 80, 40)),
      ],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
    ]), isEmpty);
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('20%', Rect.fromLTWH(145, 610, 80, 40)),
      ],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
    ]), isEmpty);
  });

  test('intervening section text blocks invalidate multi-line column matching', () {
    expect(nativeCrossBlockPairs(imageSize: size, blocks: [
      [
        ratio,
        const NativeOcrLine('20%', Rect.fromLTWH(100, 610, 80, 40)),
      ],
      [
        fiber,
        const NativeOcrLine('POLYESTER', Rect.fromLTWH(210, 612, 200, 40)),
      ],
      [const NativeOcrLine('ASTAR', Rect.fromLTWH(181, 610, 28, 40))],
    ]), isEmpty);
  });

}
