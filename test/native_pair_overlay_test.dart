import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_pair_overlay.dart';

void main() {
  const preview = Size(1920, 1080);
  const valid = {'80% pamuk': Rect.fromLTWH(.2, .3, .4, .04)};
  bool ready({
    bool android = true,
    bool rearCamera = true,
    bool portraitUp = true,
    int? rotationDegrees = 90,
    Size? previewSize = preview,
    Map<String, Rect>? normalizedBoxes = valid,
    int stableFrames = 2,
  }) => canShowNativePairOverlay(
    android: android,
    rearCamera: rearCamera,
    portraitUp: portraitUp,
    rotationDegrees: rotationDegrees,
    previewSize: previewSize,
    normalizedBoxes: normalizedBoxes,
    stableFrames: stableFrames,
  );

  test('only stable rear Android portrait 90-degree boxes can be shown', () {
    expect(ready(), isTrue);
    expect(ready(stableFrames: 1), isFalse);
    expect(ready(android: false), isFalse);
    expect(ready(rearCamera: false), isFalse);
    expect(ready(portraitUp: false), isFalse);
    expect(ready(rotationDegrees: 270), isFalse);
    expect(ready(rotationDegrees: 0), isFalse);
    expect(ready(previewSize: const Size(1080, 1920)), isFalse);
    expect(ready(previewSize: null), isFalse);
  });

  test('missing, duplicate-unsafe and out-of-frame OCR geometry hides overlay', () {
    expect(ready(normalizedBoxes: null), isFalse);
    expect(ready(normalizedBoxes: {}), isFalse);
    expect(ready(normalizedBoxes: {
      '80% pamuk': const Rect.fromLTWH(-.01, .3, .4, .04),
    }), isFalse);
    expect(ready(normalizedBoxes: {
      '80% pamuk': const Rect.fromLTWH(.2, .3, .9, .04),
    }), isFalse);
    expect(ready(normalizedBoxes: {
      '80% pamuk': const Rect.fromLTWH(.2, .3, 0, .04),
    }), isFalse);
  });

  testWidgets('provisional overlay has accessibility label and no gestures',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 300, height: 400,
        child: NativePairOverlay(normalizedBoxes: valid),
      )),
    ));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(find.bySemanticsLabel(
      'Sarı: tahmini yüzde ve elyaf satırları. Doğrulanmadı.'),
      findsOneWidget);
  });
}
