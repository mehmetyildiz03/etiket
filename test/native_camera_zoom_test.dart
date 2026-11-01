import 'dart:async';

import 'package:etiket/scan/native_camera_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zoom in uses camera range and only reports successful hardware change',
      () async {
    final calls = <double>[];
    final outcome = await changeNativeCameraZoom(
      current: 1,
      zoomIn: true,
      getMinZoomLevel: () async => 1,
      getMaxZoomLevel: () async => 6,
      setZoomLevel: (zoom) async { calls.add(zoom); },
    );
    expect(outcome.status, NativeZoomStatus.changed);
    expect(outcome.zoom, 1.5);
    expect(calls, [1.5]);
  });

  test('zoom out is bounded at the actual minimum', () async {
    var calls = 0;
    final outcome = await changeNativeCameraZoom(
      current: 1,
      zoomIn: false,
      getMinZoomLevel: () async => 1,
      getMaxZoomLevel: () async => 4,
      setZoomLevel: (_) async { calls++; },
    );
    expect(outcome.status, NativeZoomStatus.unchanged);
    expect(outcome.zoom, 1);
    expect(calls, 0);
  });

  test('zoom in clamps at hardware maximum without overshoot', () async {
    final calls = <double>[];
    final outcome = await changeNativeCameraZoom(
      current: 3.8,
      zoomIn: true,
      getMinZoomLevel: () async => 1,
      getMaxZoomLevel: () async => 4,
      setZoomLevel: (zoom) async { calls.add(zoom); },
    );
    expect(outcome.status, NativeZoomStatus.changed);
    expect(outcome.zoom, 4);
    expect(calls, [4]);
  });

  test('invalid capability range fails closed without calling hardware',
      () async {
    var calls = 0;
    final outcome = await changeNativeCameraZoom(
      current: 1,
      zoomIn: true,
      getMinZoomLevel: () async => double.nan,
      getMaxZoomLevel: () async => 5,
      setZoomLevel: (_) async { calls++; },
    );
    expect(outcome.status, NativeZoomStatus.unavailable);
    expect(outcome.zoom, 1);
    expect(calls, 0);
  });

  test('unsupported hardware does not invent a new zoom value', () async {
    final outcome = await changeNativeCameraZoom(
      current: 1.5,
      zoomIn: true,
      getMinZoomLevel: () async => 1,
      getMaxZoomLevel: () async => 6,
      setZoomLevel: (_) async { throw UnsupportedError('zoom'); },
    );
    expect(outcome.status, NativeZoomStatus.unavailable);
    expect(outcome.zoom, 1.5);
  });

  test('zoom is not reported changed until hardware request finishes',
      () async {
    final pending = Completer<void>();
    final future = changeNativeCameraZoom(
      current: 1,
      zoomIn: true,
      getMinZoomLevel: () async => 1,
      getMaxZoomLevel: () async => 3,
      setZoomLevel: (_) => pending.future,
    );
    var completed = false;
    future.then((_) { completed = true; });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    pending.complete();
    final outcome = await future;
    expect(outcome.status, NativeZoomStatus.changed);
    expect(outcome.zoom, 1.5);
  });
}
