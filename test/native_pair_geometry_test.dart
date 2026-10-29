import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_pair_geometry.dart';

void main() {
  const portrait = Size(1080, 1920);

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
