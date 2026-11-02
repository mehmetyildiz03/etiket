import 'dart:ui';

import 'package:etiket/scan/native_inline_pair_conflicts.dart';
import 'package:etiket/scan/native_spatial_pairs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(1080, 1920);
  const inline = NativeOcrLine(
      '80% PAMUK', Rect.fromLTWH(100, 500, 270, 40));

  List<String> pairs(List<List<NativeOcrLine>> blocks) =>
      nativeUnambiguousInlinePairs(imageSize: size, blocks: blocks)
          .map((candidate) => candidate.value).toList();

  test('an isolated rival fiber in another ML Kit block blocks inline pair', () {
    expect(pairs([
      [inline],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(375, 502, 140, 40))],
    ]), isEmpty);
    expect(pairs([
      [inline],
      [const NativeOcrLine('WASH KETEN', Rect.fromLTWH(375, 502, 140, 40))],
    ]), isEmpty);
  });

  test('competing percentage and bare number in a separate block fail closed', () {
    for (final rival in ['20%', '%20', '20', '%']) {
      expect(pairs([
        [inline],
        [NativeOcrLine(rival, const Rect.fromLTWH(50, 500, 45, 40))],
      ]), isEmpty, reason: rival);
    }
  });

  test('separate real rows and two complete pairs on one row survive', () {
    expect(pairs([
      [inline],
      [const NativeOcrLine('20% KETEN', Rect.fromLTWH(100, 610, 270, 40))],
    ]), ['80% pamuk', '20% keten']);
    expect(pairs([
      [inline],
      [const NativeOcrLine('20% KETEN', Rect.fromLTWH(380, 500, 270, 40))],
    ]), ['80% pamuk', '20% keten']);
    expect(pairs([
      [inline],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(500, 610, 140, 40))],
    ]), ['80% pamuk']);
  });

  test('overlapping duplicate full pairs and invalid rival boxes are unsafe', () {
    expect(pairs([
      [inline],
      [const NativeOcrLine('80% KETEN', Rect.fromLTWH(110, 500, 270, 40))],
    ]), isEmpty);
    expect(pairs([
      [inline],
      [const NativeOcrLine('KETEN', Rect.fromLTWH(-1, 500, 100, 40))],
    ]), isEmpty);
    expect(pairs([
      [inline],
      [const NativeOcrLine('IRON LOW', Rect.fromLTWH(-1, 500, 100, 40))],
    ]), ['80% pamuk']);
  });

  test('no percentage is ever inferred from an isolated fiber or bare ratio', () {
    expect(pairs([
      [const NativeOcrLine('80 PAMUK', Rect.fromLTWH(100, 500, 270, 40))],
    ]), isEmpty);
    expect(pairs([
      [const NativeOcrLine('80', Rect.fromLTWH(100, 500, 70, 40))],
      [const NativeOcrLine('PAMUK', Rect.fromLTWH(180, 500, 140, 40))],
    ]), isEmpty);
  });

  test('dense or malformed camera geometry fails closed without guessing', () {
    expect(nativeUnambiguousInlinePairs(
      imageSize: Size.zero, blocks: [[inline]]), isEmpty);
    expect(pairs([
      [inline],
      List.generate(256, (i) => NativeOcrLine('CARE $i',
          Rect.fromLTWH(10, i * 5.0, 100, 4))),
    ]), isEmpty);
    expect(pairs([
      [const NativeOcrLine('80% PAMUK',
          Rect.fromLTWH(-1, 500, 270, 40))],
    ]), isEmpty);
  });
}
