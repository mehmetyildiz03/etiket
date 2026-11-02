import 'dart:typed_data';
import 'dart:ui';

import 'package:etiket/scan/live_frame_quality.dart';
import 'package:etiket/scan/native_live_line_quality.dart';
import 'package:etiket/scan/native_pair_pixel_quality.dart';
import 'package:etiket/scan/native_spatial_pairs.dart';
import 'package:etiket/scan/native_split_missing_percent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(1080, 1920);
  const bare = NativeOcrLine('80', Rect.fromLTWH(100, 500, 80, 40));
  const fiber = NativeOcrLine('PAMUK', Rect.fromLTWH(210, 502, 160, 40));

  test('split bare ratio and fiber trigger refocus, not a made-up pair', () {
    expect(nativeSplitMissingPercentHint(
      imageSize: size, lines: [bare, fiber]), isTrue);
    expect(nativeSpatialPairs(imageSize: size, lines: [bare, fiber]), isEmpty);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      const NativeOcrLine('KETEN', Rect.fromLTWH(100, 600, 160, 40)),
      const NativeOcrLine('20', Rect.fromLTWH(280, 602, 65, 40)),
    ]), isTrue);
  });

  test('actual percent sign and separate percent token do not raise hint', () {
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      const NativeOcrLine('80%', Rect.fromLTWH(100, 500, 80, 40)), fiber,
    ]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('%', Rect.fromLTWH(185, 500, 18, 40)), fiber,
    ]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('20%', Rect.fromLTWH(185, 500, 40, 40)), fiber,
    ]), isFalse);
  });

  test('distant, stacked, competing or unboxed tokens fail closed', () {
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('PAMUK', Rect.fromLTWH(500, 500, 160, 40)),
    ]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('PAMUK', Rect.fromLTWH(210, 560, 160, 40)),
    ]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, fiber, const NativeOcrLine('KETEN', Rect.fromLTWH(205, 502, 160, 40)),
    ]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('KETEN', Rect.fromLTWH(-1, 502, 160, 40)), fiber,
    ]), isFalse);
  });

  test('invalid ratios, care text and invalid geometry never infer anything', () {
    for (final text in ['0', '120', '1000', '80%', 'WASH 30', '30 C']) {
      expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
        NativeOcrLine(text, bare.box), fiber,
      ]), isFalse, reason: text);
    }
    expect(nativeSplitMissingPercentHint(imageSize: Size.zero,
      lines: [bare, fiber]), isFalse);
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, const NativeOcrLine('PAMUK', Rect.fromLTWH(-1, 502, 160, 40)),
    ]), isFalse);
  });

  test('different rows may contain valid printed pairs without hiding a hint', () {
    expect(nativeSplitMissingPercentHint(imageSize: size, lines: [
      bare, fiber,
      const NativeOcrLine('20%', Rect.fromLTWH(100, 620, 80, 40)),
      const NativeOcrLine('KETEN', Rect.fromLTWH(210, 620, 160, 40)),
    ]), isTrue);
  });


  test('split number and fiber drive exposure from their real pixel region', () {
    const width = 128, height = 96;
    const good = Rect.fromLTRB(8 / 128, 8 / 96, 48 / 128, 40 / 96);
    final split = nativeSplitMissingPercentRegions(
      imageSize: const Size(128, 96),
      lines: const [
        NativeOcrLine('20', Rect.fromLTRB(68, 8, 84, 40)),
        NativeOcrLine('KETEN', Rect.fromLTRB(87, 8, 116, 40)),
      ],
    );
    expect(split, const [Rect.fromLTRB(68, 8, 116, 40)]);
    final pixels = Uint8List(width * height)
      ..fillRange(0, width * height, 245);
    for (var y = 8; y < 40; y++) {
      for (var x = 8; x < 48; x++) {
        if (x.isEven) pixels[y * width + x] = 10;
      }
    }
    for (var y = 4; y < 44; y++) {
      for (var x = 64; x < 120; x++) {
        pixels[y * width + x] = 10;
      }
    }
    LiveFrameQuality quality(List<Rect> boxes) =>
        assessNativeMatchedPairQuality(
          bytes: pixels, width: width, height: height,
          rowStride: width, pixelStride: 1, bgra: false,
          rotationDegrees: 0, normalizedBoxes: boxes,
        );
    final goodOnly = nativeLiveQualityRegions(
      imageSize: const Size(128, 96),
      matchedBoxes: const {'80:pamuk': good},
      incompleteLineBoxes: const [], missingPercent: false,
    )!;
    expect(quality(goodOnly), LiveFrameQuality.usable);
    final both = nativeLiveQualityRegions(
      imageSize: const Size(128, 96),
      matchedBoxes: const {'80:pamuk': good},
      incompleteLineBoxes: split, missingPercent: true,
    )!;
    expect(both, hasLength(2));
    expect(quality(both), LiveFrameQuality.dark);
    // This is exposure guidance only; no percent is manufactured or approved.
    expect(nativeSpatialPairs(
      imageSize: const Size(128, 96),
      lines: const [
        NativeOcrLine('20', Rect.fromLTRB(68, 8, 84, 40)),
        NativeOcrLine('KETEN', Rect.fromLTRB(87, 8, 116, 40)),
      ],
    ), isEmpty);
  });

  test('split region extraction rejects ambiguous or intervening tokens', () {
    expect(nativeSplitMissingPercentRegions(
      imageSize: size,
      lines: [
        bare, fiber,
        const NativeOcrLine('%', Rect.fromLTWH(184, 500, 20, 40)),
      ],
    ), isEmpty);
    expect(nativeSplitMissingPercentRegions(
      imageSize: size,
      lines: [
        bare, fiber,
        const NativeOcrLine('KETEN', Rect.fromLTWH(205, 502, 160, 40)),
      ],
    ), isEmpty);
    expect(nativeSplitMissingPercentRegions(
      imageSize: size,
      lines: [
        bare, const NativeOcrLine('PAMUK', Rect.fromLTWH(-1, 502, 160, 40)),
      ],
    ), isEmpty);
  });
}
