import 'dart:async';

import 'package:etiket/scan/native_camera_torch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit light-on request succeeds only after hardware response',
      () async {
    final calls = <bool>[];
    final outcome = await changeNativeCameraTorch(
      currentlyEnabled: false,
      setTorchEnabled: (enabled) async { calls.add(enabled); },
    );
    expect(calls, [true]);
    expect(outcome.status, NativeTorchStatus.changed);
    expect(outcome.enabled, true);
  });

  test('light-off sends an explicit off request', () async {
    final calls = <bool>[];
    final outcome = await changeNativeCameraTorch(
      currentlyEnabled: true,
      setTorchEnabled: (enabled) async { calls.add(enabled); },
    );
    expect(calls, [false]);
    expect(outcome.status, NativeTorchStatus.changed);
    expect(outcome.enabled, false);
  });

  test('unsupported torch does not falsely claim illumination', () async {
    final outcome = await changeNativeCameraTorch(
      currentlyEnabled: false,
      setTorchEnabled: (_) async { throw UnsupportedError('torch'); },
    );
    expect(outcome.status, NativeTorchStatus.unavailable);
    expect(outcome.enabled, false);
  });

  test('failed off request keeps last confirmed state for user warning',
      () async {
    final outcome = await changeNativeCameraTorch(
      currentlyEnabled: true,
      setTorchEnabled: (_) async { throw StateError('camera detached'); },
    );
    expect(outcome.status, NativeTorchStatus.unavailable);
    expect(outcome.enabled, true);
  });

  test('pending hardware request never reports light on prematurely',
      () async {
    final pending = Completer<void>();
    final future = changeNativeCameraTorch(
      currentlyEnabled: false,
      setTorchEnabled: (_) => pending.future,
    );
    var completed = false;
    future.then((_) { completed = true; });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    pending.complete();
    final outcome = await future;
    expect(outcome.status, NativeTorchStatus.changed);
    expect(outcome.enabled, true);
  });
}
