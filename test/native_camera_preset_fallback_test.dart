import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_camera_preset_fallback.dart';

class _FakeStream {
  _FakeStream(this.preset);
  final ResolutionPreset preset;
  bool disposed = false;
}

void main() {
  test('ultraHigh stream success does not lower live resolution', () async {
    final attempts = <ResolutionPreset>[];
    final opened = await openNativeCameraWithPresetFallback<_FakeStream>(
      cancelled: () => false,
      create: (preset) {
        attempts.add(preset);
        return _FakeStream(preset);
      },
      initializeAndStart: (_) async {},
      dispose: (camera) async { camera.disposed = true; },
    );
    expect(attempts, [ResolutionPreset.ultraHigh]);
    expect(opened.preset, ResolutionPreset.ultraHigh);
    expect(opened.disposed, false);
  });

  test('failed ultraHigh stream is disposed before high stream opens', () async {
    final attempts = <_FakeStream>[];
    final opened = await openNativeCameraWithPresetFallback<_FakeStream>(
      cancelled: () => false,
      create: (preset) {
        if (attempts.isNotEmpty) expect(attempts.last.disposed, true);
        final camera = _FakeStream(preset);
        attempts.add(camera);
        return camera;
      },
      initializeAndStart: (camera) async {
        if (camera.preset == ResolutionPreset.ultraHigh) {
          throw StateError('stream unsupported');
        }
      },
      dispose: (camera) async { camera.disposed = true; },
    );
    expect(attempts.map((c) => c.preset),
        [ResolutionPreset.ultraHigh, ResolutionPreset.high]);
    expect(attempts.first.disposed, true);
    expect(opened.preset, ResolutionPreset.high);
    expect(opened.disposed, false);
  });

  test('both failed streams are disposed and the failure is surfaced', () async {
    final attempts = <_FakeStream>[];
    await expectLater(
      openNativeCameraWithPresetFallback<_FakeStream>(
        cancelled: () => false,
        create: (preset) {
          final camera = _FakeStream(preset);
          attempts.add(camera);
          return camera;
        },
        initializeAndStart: (_) async { throw StateError('cannot stream'); },
        dispose: (camera) async { camera.disposed = true; },
      ),
      throwsStateError,
    );
    expect(attempts.length, 2);
    expect(attempts.every((c) => c.disposed), true);
  });

  test('lifecycle cancellation disposes attempt and never opens next camera', () async {
    var cancelled = false;
    final attempts = <_FakeStream>[];
    await expectLater(
      openNativeCameraWithPresetFallback<_FakeStream>(
        cancelled: () => cancelled,
        create: (preset) {
          final camera = _FakeStream(preset);
          attempts.add(camera);
          return camera;
        },
        initializeAndStart: (_) async { cancelled = true; },
        dispose: (camera) async { camera.disposed = true; },
      ),
      throwsStateError,
    );
    expect(attempts.length, 1);
    expect(attempts.single.disposed, true);
  });
  test('failed cleanup prevents a second camera from claiming the device', () async {
    final attempts = <ResolutionPreset>[];
    await expectLater(
      openNativeCameraWithPresetFallback<_FakeStream>(
        cancelled: () => false,
        create: (preset) {
          attempts.add(preset);
          return _FakeStream(preset);
        },
        initializeAndStart: (_) async { throw StateError('stream unsupported'); },
        dispose: (_) async { throw StateError('camera release failed'); },
      ),
      throwsStateError,
    );
    expect(attempts, [ResolutionPreset.ultraHigh],
        reason: 'never open a second stream while first may own the camera');
  });

}
