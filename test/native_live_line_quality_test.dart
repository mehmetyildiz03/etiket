import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/live_frame_quality.dart';
import 'package:etiket/scan/native_live_line_quality.dart';
import 'package:etiket/scan/native_pair_pixel_quality.dart';

void main() {
  test('dark missing-percent row is measured alongside a clear matched row', () {
    const width = 128, height = 96;
    final pixels = Uint8List(width * height)
      ..fillRange(0, width * height, 245);
    // A bright legible 80% PAMUK line and a genuinely dark 20 KETEN line.
    // Scene/first-pair-only measurement would hide the incomplete row.
    for (var y = 8; y < 40; y++) {
      for (var x = 8; x < 48; x++) {
        if (x.isEven) pixels[y * width + x] = 10;
      }
    }
    for (var y = 4; y < 44; y++) {
      for (var x = 68; x < 116; x++) {
        pixels[y * width + x] = 10;
      }
    }
    const matched = Rect.fromLTRB(8 / 128, 8 / 96, 48 / 128, 40 / 96);
    const incomplete = Rect.fromLTRB(72, 8, 112, 40);
    LiveFrameQuality quality(List<Rect> regions) =>
        assessNativeMatchedPairQuality(
          bytes: pixels, width: width, height: height,
          rowStride: width, pixelStride: 1, bgra: false,
          rotationDegrees: 0, normalizedBoxes: regions,
        );

    final firstOnly = nativeLiveQualityRegions(
      imageSize: const Size(128, 96),
      matchedBoxes: const {'80:pamuk': matched},
      incompleteLineBoxes: const [incomplete],
      missingPercent: false,
    )!;
    expect(firstOnly, hasLength(1));
    expect(quality(firstOnly), LiveFrameQuality.usable);

    final both = nativeLiveQualityRegions(
      imageSize: const Size(128, 96),
      matchedBoxes: const {'80:pamuk': matched},
      incompleteLineBoxes: const [incomplete],
      missingPercent: true,
    )!;
    expect(both, hasLength(2));
    expect(quality(both), LiveFrameQuality.dark,
        reason: 'the actual unreadable percentage line must drive light advice');
  });

  test('an incomplete line can receive local light advice without any pair', () {
    final regions = nativeLiveQualityRegions(
      imageSize: const Size(100, 80),
      matchedBoxes: null,
      incompleteLineBoxes: const [Rect.fromLTRB(10, 20, 70, 50)],
      missingPercent: true,
    );
    expect(regions, const [Rect.fromLTRB(.1, .25, .7, .625)]);
    // Still only a partial OCR hint: no percentage or fiber is invented.
  });

  test('missing, malformed, and excess partial geometry fails closed', () {
    List<Rect>? regions(List<Rect> incomplete, {Size? size = const Size(100, 80)}) =>
        nativeLiveQualityRegions(
          imageSize: size,
          matchedBoxes: const {'80:pamuk': Rect.fromLTRB(.1, .1, .4, .3)},
          incompleteLineBoxes: incomplete,
          missingPercent: true,
        );
    expect(regions([]), isNull, reason: 'unlocated missed mark is not measured as a good pair');
    expect(regions(const [Rect.fromLTRB(-1, 10, 30, 40)]), isNull);
    expect(regions(const [Rect.fromLTRB(10, 10, 110, 40)]), isNull);
    expect(regions(const [Rect.fromLTRB(10, 10, 10, 40)]), isNull);
    expect(regions(List.filled(8, const Rect.fromLTRB(10, 10, 30, 40))), isNull);
    expect(regions(const [Rect.fromLTRB(10, 10, 30, 40)], size: null), isNull);
    expect(nativeLiveQualityRegions(
      imageSize: const Size(100, 80),
      matchedBoxes: const {'bad': Rect.fromLTRB(-.1, .1, .3, .4)},
      incompleteLineBoxes: const [],
      missingPercent: false,
    ), isNull);
  });
}
