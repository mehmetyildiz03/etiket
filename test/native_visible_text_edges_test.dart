import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_visible_text_edges.dart';

void main() {
  const portrait = Size(1080, 1920);
  const matched = Rect.fromLTWH(240, 800, 550, 60);

  test('visible non-pair text at edge prompts conservative move-back cue', () {
    expect(visibleTextTouchesFrameEdge(
      imageSize: portrait,
      matchedPairCount: 1,
      textLineBoxes: [matched, const Rect.fromLTWH(10, 680, 300, 48)],
    ), isTrue);
    expect(visibleTextTouchesFrameEdge(
      imageSize: portrait,
      matchedPairCount: 1,
      textLineBoxes: [matched, const Rect.fromLTWH(230, 680, 300, 48)],
    ), isFalse);
  });

  test('a single OCR line, no percentage-fiber pair, or too many lines fails closed', () {
    expect(visibleTextTouchesFrameEdge(
      imageSize: portrait,
      matchedPairCount: 1,
      textLineBoxes: [const Rect.fromLTWH(10, 800, 400, 60)],
    ), isFalse);
    expect(visibleTextTouchesFrameEdge(
      imageSize: portrait,
      matchedPairCount: 0,
      textLineBoxes: [matched, const Rect.fromLTWH(10, 680, 300, 48)],
    ), isFalse);
    expect(visibleTextTouchesFrameEdge(
      imageSize: portrait,
      matchedPairCount: 1,
      textLineBoxes: List.filled(65, matched),
    ), isFalse);
  });

  test('bad dimensions and even one malformed line reject the edge hint', () {
    for (final imageSize in [Size.zero, const Size(9000, 9000)]) {
      expect(visibleTextTouchesFrameEdge(
        imageSize: imageSize,
        matchedPairCount: 1,
        textLineBoxes: [matched, const Rect.fromLTWH(10, 680, 300, 48)],
      ), isFalse);
    }
    for (final bad in [
      const Rect.fromLTWH(-1, 200, 300, 40),
      const Rect.fromLTWH(100, 200, 0, 40),
      const Rect.fromLTWH(900, 200, 300, 40),
    ]) {
      expect(visibleTextTouchesFrameEdge(
        imageSize: portrait,
        matchedPairCount: 1,
        textLineBoxes: [matched, bad],
      ), isFalse);
    }
  });

  test('top and bottom clipping cues are detected without green readiness', () {
    for (final edge in [
      const Rect.fromLTWH(200, 1, 300, 50),
      const Rect.fromLTWH(200, 1880, 300, 39),
    ]) {
      expect(visibleTextTouchesFrameEdge(
        imageSize: portrait,
        matchedPairCount: 2,
        textLineBoxes: [matched, edge],
      ), isTrue);
    }
  });
}
