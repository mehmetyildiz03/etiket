import 'package:etiket/scan/live_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

LiveFrameSample frame(int sequence, String text,
        {bool sharp = true, bool complete = true}) =>
    LiveFrameSample(
      sequence: sequence,
      ocrText: text,
      imageQualityOk: sharp,
      wholeLabelVisible: complete,
    );

void main() {
  test('a textile word alone never turns the camera green', () {
    final tracker = LiveReadinessTracker();
    for (var n = 1; n <= 5; n++) {
      final cue = tracker.observe(frame(n, 'PAMUK'));
      expect(cue.level, LiveReadinessLevel.partial);
      expect(cue.detectedPairs, isEmpty);
    }
  });

  test('only repeated complete percent-fiber sections become green', () {
    final tracker = LiveReadinessTracker();
    final first = tracker.observe(frame(1, '70% pamuk\n30% polyester'));
    expect(first.level, LiveReadinessLevel.partial);
    expect(first.detectedPairs.map((p) => p.fiber),
        ['Pamuk', 'Polyester']);
    expect(first.detectedPairs.map((p) => p.percentage), [70, 30]);
    expect(tracker.observe(frame(2, 'CO 70%\nPES 30%')).isReadyToCapture, false);
    final third = tracker.observe(frame(3, '70% cotton 30% polyester'));
    expect(third.isReadyToCapture, true);
    expect(third.stableFrames, 3);
    expect(third.message, contains('doğrula'));
  });

  test('duplicate and out-of-order frames do not count as agreement', () {
    final tracker = LiveReadinessTracker();
    tracker.observe(frame(5, '100% cotton'));
    expect(tracker.observe(frame(5, '100% cotton')).stableFrames, 1);
    expect(tracker.observe(frame(4, '100% cotton')).stableFrames, 1);
    expect(tracker.observe(frame(6, '100% cotton')).isReadyToCapture, false);
    expect(tracker.observe(frame(7, '100% cotton')).isReadyToCapture, true);
  });

  test('changing percentage pairs or section context resets stability', () {
    final tracker = LiveReadinessTracker();
    tracker.observe(frame(1, '80% pamuk 20% polyester'));
    tracker.observe(frame(2, '80% pamuk 20% polyester'));
    expect(tracker.observe(frame(3, '70% pamuk 30% polyester')).stableFrames, 1);
    expect(tracker.observe(frame(4, '70% pamuk 30% polyester')).isReadyToCapture, false);
    expect(tracker.observe(frame(5, '70% pamuk 30% polyester')).isReadyToCapture, true);
    expect(tracker.observe(frame(6, 'Astar: 70% pamuk 30% polyester')).isReadyToCapture, false);
  });

  test('quality and full-frame coverage must be independently established', () {
    final tracker = LiveReadinessTracker();
    for (var n = 1; n <= 4; n++) {
      expect(tracker.observe(frame(n, '100% pamuk', sharp: false))
          .isReadyToCapture, false);
    }
    for (var n = 5; n <= 8; n++) {
      expect(tracker.observe(frame(n, '100% pamuk', complete: false))
          .isReadyToCapture, false);
    }
    expect(tracker.observe(frame(9, '100% pamuk')).stableFrames, 1);
  });

  test('missing, malformed and cross-section ratios never go green', () {
    for (final text in [
      '70% pamuk polyester',
      '70? pamuk 30% polyester',
      '2026 COTTON',
      'Shell: 80% CO\nLining: 100% PES',
      '100% P',
    ]) {
      final tracker = LiveReadinessTracker();
      for (var n = 1; n <= 4; n++) {
        expect(tracker.observe(frame(n, text)).isReadyToCapture, false,
            reason: text);
      }
    }
  });

  test('an empty frame resets green and a new session starts clean', () {
    final tracker = LiveReadinessTracker();
    tracker.observe(frame(1, '100% pamuk'));
    tracker.observe(frame(2, '100% pamuk'));
    expect(tracker.observe(frame(3, '100% pamuk')).isReadyToCapture, true);
    expect(tracker.observe(frame(4, '')).level, LiveReadinessLevel.searching);
    expect(tracker.observe(frame(5, '100% pamuk')).stableFrames, 1);
    tracker.reset();
    expect(tracker.current.level, LiveReadinessLevel.searching);
    expect(tracker.observe(frame(1, '100% pamuk')).stableFrames, 1);
  });

  test('tracker does not allow a single frame to verify anything', () {
    expect(() => LiveReadinessTracker(requiredStableFrames: 1),
        throwsArgumentError);
  });
}
