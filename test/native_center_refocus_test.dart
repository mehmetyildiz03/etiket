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
}
