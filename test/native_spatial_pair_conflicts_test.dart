import 'dart:ui';

import 'package:etiket/scan/native_spatial_pair_conflicts.dart';
import 'package:etiket/scan/native_spatial_pairs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(1080, 1920);
  const ratio = NativeOcrLine(
      '80%', Rect.fromLTWH(100, 500, 80, 40));
  const fiber = NativeOcrLine(
      'PAMUK', Rect.fromLTWH(210, 502, 160, 40));

  List<String> pairs(List<List<NativeOcrLine>> blocks) =>
      nativeUnambiguousSpatialPairs(imageSize: size, blocks: blocks)
          .map((pair) => pair.value)
          .toList();

  test('separate OCR block with rival fiber invalidates same-block pair', () {
    expect(pairs([
      [ratio, fiber],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(375, 502, 140, 40))],
    ]), isEmpty);
  });

  test('competing percent, bare number and glyph cannot claim the same row',
      () {
    for (final rival in ['20%', '20', '%']) {
      expect(pairs([
        [ratio, fiber],
        [NativeOcrLine(rival, const Rect.fromLTWH(48, 502, 47, 40))],
      ]), isEmpty, reason: rival);
    }
  });

  test('intervening text in another block prevents a false join', () {
    expect(pairs([
      [ratio, fiber],
      [const NativeOcrLine('OTHER', Rect.fromLTWH(182, 500, 26, 40))],
    ]), isEmpty);
  });

  test('different rows and distant unrelated text preserve literal pairs',
      () {
    expect(pairs([
      [ratio, fiber],
      [const NativeOcrLine('20% KETEN', Rect.fromLTWH(100, 610, 270, 40))],
      [const NativeOcrLine('WASH', Rect.fromLTWH(700, 500, 90, 40))],
    ]), ['80% pamuk']);
  });

  test('unlocated rival and duplicate composition row fail closed', () {
    expect(pairs([
      [ratio, fiber],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(-1, 500, 90, 40))],
    ]), isEmpty);
    expect(pairs([
      [ratio, fiber],
      [
        const NativeOcrLine('80%', Rect.fromLTWH(100, 610, 80, 40)),
        const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 612, 160, 40)),
      ],
    ]), isEmpty);
  });

  test('never invents a missing printed percent or joins vertical tokens',
      () {
    expect(pairs([
      [const NativeOcrLine('80', Rect.fromLTWH(100, 500, 80, 40)), fiber],
    ]), isEmpty);
    expect(pairs([
      [ratio, const NativeOcrLine(
          'PAMUK', Rect.fromLTWH(210, 560, 160, 40))],
    ]), isEmpty);
  });
}
