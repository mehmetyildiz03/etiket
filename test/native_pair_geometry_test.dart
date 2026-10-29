import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_pair_geometry.dart';

void main() {
  const portrait = Size(1080, 1920);

  test('spatially stable percentage-fiber boxes agree despite small jitter', () {
    final a = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(200, 500, 400, 60),
      '20% polyester': const Rect.fromLTWH(200, 600, 400, 60),
    });
    final b = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(205, 506, 398, 60),
      '20% polyester': const Rect.fromLTWH(205, 606, 398, 60),
    });
    expect(nativePairBoxesAgree(a, b), isTrue);
  });

  test('same words and same centroid do not hide swapped line positions', () {
    final before = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(200, 400, 400, 60),
      '20% polyester': const Rect.fromLTWH(200, 1000, 400, 60),
    });
    final after = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(200, 1000, 400, 60),
      '20% polyester': const Rect.fromLTWH(200, 400, 400, 60),
    });
    expect(nativePairBoxesAgree(before, after), isFalse);
  });

  test('pair set, zoom changes and missing boxes never count as stable', () {
    final first = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(200, 500, 400, 60),
    });
    final different = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% keten': const Rect.fromLTWH(200, 500, 400, 60),
    });
    final zoomed = normalizeNativePairBoxes(imageSize: portrait, pairBoxes: {
      '80% pamuk': const Rect.fromLTWH(100, 450, 800, 120),
    });
    expect(nativePairBoxesAgree(first, different), isFalse);
    expect(nativePairBoxesAgree(first, zoomed), isFalse);
    expect(nativePairBoxesAgree(first, null), isFalse);
  });

  test('ambiguous duplicate or out-of-frame OCR boxes fail closed', () {
    expect(normalizeNativePairBoxes(imageSize: portrait,
      pairBoxes: {'80% pamuk': const Rect.fromLTWH(200, 500, 400, 60)},
      duplicatePair: true), isNull);
    expect(normalizeNativePairBoxes(imageSize: portrait,
      pairBoxes: {'80% pamuk': const Rect.fromLTWH(-1, 500, 400, 60)}), isNull);
    expect(normalizeNativePairBoxes(imageSize: portrait,
      pairBoxes: {'80% pamuk': const Rect.fromLTWH(200, 500, 400, 60)}),
      isNotNull);
  });


  test('Android OCR box dimensions follow the exact input rotation', () {
    for (final angle in [90, 270]) {
      expect(nativeOcrImageSize(width: 1920, height: 1080,
        rotationDegrees: angle, android: true), portrait);
    }
    for (final angle in [0, 180]) {
      expect(nativeOcrImageSize(width: 1920, height: 1080,
        rotationDegrees: angle, android: true), const Size(1920, 1080));
    }
    // iOS geometry must not speculate about rotated boxes; its framing
    // remains disabled pending real-device orientation calibration.
    expect(nativeOcrImageSize(width: 1920, height: 1080,
      rotationDegrees: 90, android: false), const Size(1920, 1080));
  });

  test('malformed orientation and dimensions fail closed', () {
    expect(nativeOcrImageSize(width: 1920, height: 1080,
      rotationDegrees: 45, android: true), isNull);
    expect(nativeOcrImageSize(width: 0, height: 1080,
      rotationDegrees: 90, android: true), isNull);
    expect(nativeOcrImageSize(width: 9000, height: 9000,
      rotationDegrees: 90, android: true), isNull);
  });

  test('small matched line asks for closer focus, not green', () {
    final result = assessNativePairGeometry(imageSize: portrait,
      pairLineBoxes: [const Rect.fromLTWH(200, 600, 380, 24)]);
    expect(result.hint, NativeFramingHint.moveCloser);
    expect(result.center, const Offset(390 / 1080, 612 / 1920));
  });

  test('edge matched line asks to move back even when small', () {
    final result = assessNativePairGeometry(imageSize: portrait,
      pairLineBoxes: [const Rect.fromLTWH(1010, 600, 65, 18)]);
    expect(result.hint, NativeFramingHint.moveBack);
  });

  test('visible matched lines give steady hint and normalized center', () {
    final result = assessNativePairGeometry(imageSize: portrait,
      pairLineBoxes: [const Rect.fromLTWH(200, 500, 400, 60),
                      const Rect.fromLTWH(200, 600, 400, 60)]);
    expect(result.hint, NativeFramingHint.steady);
    // Floating-point accumulation can differ by a few ULPs from division.
    expect(result.center, isNotNull);
    expect(result.center!.dx, closeTo(400 / 1080, 1e-12));
    expect(result.center!.dy, closeTo(580 / 1920, 1e-12));
  });

  test('rotated image dimensions are used, never raw landscape dimensions', () {
    final result = assessNativePairGeometry(imageSize: portrait,
      pairLineBoxes: [const Rect.fromLTWH(800, 1200, 200, 50)]);
    expect(result.hint, NativeFramingHint.steady);
    expect(result.center!.dy, greaterThan(.6));
  });

  test('12MP still-sized stream coordinates remain supported', () {
    final result = assessNativePairGeometry(
      imageSize: const Size(3024, 4032),
      pairLineBoxes: [const Rect.fromLTWH(700, 1400, 900, 80)]);
    expect(result.hint, NativeFramingHint.steady);
    expect(result.center, isNotNull);
  });

  test('invalid, empty and out-of-frame boxes fail closed', () {
    for (final boxes in <List<Rect>>[
      [], [const Rect.fromLTWH(-2, 20, 50, 50)],
      [const Rect.fromLTWH(100, 100, 0, 50)],
      [const Rect.fromLTWH(1000, 100, 100, 50)],
      [const Rect.fromLTWH(100, 100, 100, 50),
       const Rect.fromLTWH(100, 1900, 100, 50)],
    ]) {
      final result = assessNativePairGeometry(
        imageSize: portrait, pairLineBoxes: boxes);
      expect(result.hint, NativeFramingHint.unknown);
      expect(result.center, isNull);
    }
    expect(assessNativePairGeometry(imageSize: Size.zero,
      pairLineBoxes: [const Rect.fromLTWH(0, 0, 1, 1)]).hint,
      NativeFramingHint.unknown);
  });
}
