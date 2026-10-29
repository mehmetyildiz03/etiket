import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_camera_recovery.dart';

void main() {
  test('successful full still stops preview and never restarts it', () async {
    final calls = <String>[];
    final result = await takeNativeStillWithRecovery<String>(
      stopPreview: () async => calls.add('stop'),
      takeStill: () async { calls.add('still'); return '/private/still.jpg'; },
      resumePreview: () async => calls.add('resume'),
    );
    expect(result.photo, '/private/still.jpg');
    expect(result.streamRecovered, isFalse);
    expect(calls, ['stop', 'still']);
  });

  test('failed still restarts stream for an in-place retry', () async {
    final calls = <String>[];
    final result = await takeNativeStillWithRecovery<String>(
      stopPreview: () async => calls.add('stop'),
      takeStill: () async {
        calls.add('still');
        throw StateError('synthetic camera failure');
      },
      resumePreview: () async => calls.add('resume'),
    );
    expect(result.photo, isNull);
    expect(result.streamRecovered, isTrue);
    expect(calls, ['stop', 'still', 'resume']);
  });

  test('failed stop never attempts still and recovers existing preview', () async {
    final calls = <String>[];
    final result = await takeNativeStillWithRecovery<String>(
      stopPreview: () async {
        calls.add('stop');
        throw StateError('synthetic stop failure');
      },
      takeStill: () async { calls.add('still'); return 'unreachable'; },
      resumePreview: () async => calls.add('resume'),
    );
    expect(result.photo, isNull);
    expect(result.streamRecovered, isTrue);
    expect(calls, ['stop', 'resume']);
  });

  test('failed stream recovery reports fallback, never invents a still', () async {
    final result = await takeNativeStillWithRecovery<String>(
      stopPreview: () async {},
      takeStill: () async => throw StateError('synthetic still failure'),
      resumePreview: () async => throw StateError('synthetic restart failure'),
    );
    expect(result.photo, isNull);
    expect(result.streamRecovered, isFalse);
  });
}
