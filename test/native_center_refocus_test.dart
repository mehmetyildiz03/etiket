import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_center_refocus.dart';

void main() {
  test('center autofocus and exposure use normalized safe preview center', () async {
    final calls = <String>[];
    final result = await requestNativeCenterRefocus(
      setFocusPoint: (Offset point) async {
        expect(point, const Offset(0.5, 0.5));
        calls.add('focus');
      },
      setExposurePoint: (Offset point) async {
        expect(point, const Offset(0.5, 0.5));
        calls.add('exposure');
      },
    );
    expect(calls, ['focus', 'exposure']);
    expect(result, NativeCenterRefocusResult.focusAndExposureRequested);
  });

  test('unsupported exposure does not prevent hardware focus request', () async {
    final result = await requestNativeCenterRefocus(
      setFocusPoint: (_) async {},
      setExposurePoint: (_) async { throw UnsupportedError('exposure'); },
    );
    expect(result, NativeCenterRefocusResult.focusOnlyRequested);
  });

  test('unsupported focus still attempts exposure without claiming focus', () async {
    var exposureCalls = 0;
    final result = await requestNativeCenterRefocus(
      setFocusPoint: (_) async { throw UnsupportedError('focus'); },
      setExposurePoint: (_) async { exposureCalls++; },
    );
    expect(exposureCalls, 1);
    expect(result, NativeCenterRefocusResult.exposureOnlyRequested);
  });

  test('both unsupported returns unavailable; never reports successful focus', () async {
    final result = await requestNativeCenterRefocus(
      setFocusPoint: (_) async { throw StateError('camera closed'); },
      setExposurePoint: (_) async { throw StateError('camera closed'); },
    );
    expect(result, NativeCenterRefocusResult.unavailable);
  });

  test('tap maps non-square preview coordinates to normalized camera point', () {
    expect(nativePreviewTapPoint(const Offset(50, 75), const Size(200, 100)),
        const Offset(0.25, 0.75));
    expect(nativePreviewTapPoint(const Offset(100, 50), const Size(200, 100)),
        const Offset(0.5, 0.5));
  });

  test('tap near edges stays inside safe focus range', () {
    expect(nativePreviewTapPoint(const Offset(0, 0), const Size(200, 100)),
        const Offset(0.05, 0.05));
    expect(nativePreviewTapPoint(const Offset(200, 100), const Size(200, 100)),
        const Offset(0.95, 0.95));
  });

  test('invalid or outside-preview taps never request hardware focus', () {
    expect(nativePreviewTapPoint(const Offset(-1, 30), const Size(200, 100)),
        isNull);
    expect(nativePreviewTapPoint(const Offset(201, 30), const Size(200, 100)),
        isNull);
    expect(nativePreviewTapPoint(const Offset(20, 30), const Size(0, 100)),
        isNull);
    expect(nativePreviewTapPoint(const Offset(double.nan, 30),
        const Size(200, 100)), isNull);
  });

  test('tap requests focus and exposure at the same actual preview point', () async {
    final calls = <Offset>[];
    final result = await requestNativeCenterRefocus(
      point: const Offset(0.25, 0.75),
      setFocusPoint: (point) async { calls.add(point); },
      setExposurePoint: (point) async { calls.add(point); },
    );
    expect(calls, [const Offset(0.25, 0.75), const Offset(0.25, 0.75)]);
    expect(result, NativeCenterRefocusResult.focusAndExposureRequested);
  });

  test('out-of-range point fails closed without hardware calls', () async {
    var calls = 0;
    final result = await requestNativeCenterRefocus(
      point: const Offset(1.5, 0.5),
      setFocusPoint: (_) async { calls++; },
      setExposurePoint: (_) async { calls++; },
    );
    expect(calls, 0);
    expect(result, NativeCenterRefocusResult.unavailable);
  });
}
