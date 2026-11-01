import 'package:etiket/scan/native_live_sampling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final origin = DateTime.utc(2026, 11, 1);

  test('first frame retains conservative default pacing', () {
    expect(nativeLiveSampleInterval(null),
        const Duration(milliseconds: 1800));
    expect(nativeLiveSampleDue(
      previousSample: origin,
      now: origin.add(const Duration(milliseconds: 1799)),
      previousOcrDuration: null,
    ), isFalse);
    expect(nativeLiveSampleDue(
      previousSample: origin,
      now: origin.add(const Duration(milliseconds: 1800)),
      previousOcrDuration: null,
    ), isTrue);
  });

  test('fast OCR allows more frequent fresh observations without overlap', () {
    const cost = Duration(milliseconds: 180);
    expect(nativeLiveSampleInterval(cost),
        const Duration(milliseconds: 1000));
    expect(nativeLiveSampleDue(
      previousSample: origin,
      now: origin.add(const Duration(milliseconds: 999)),
      previousOcrDuration: cost,
    ), isFalse);
    expect(nativeLiveSampleDue(
      previousSample: origin,
      now: origin.add(const Duration(seconds: 1)),
      previousOcrDuration: cost,
    ), isTrue);
  });

  test('slow OCR backs off and caps pacing for responsiveness', () {
    expect(nativeLiveSampleInterval(const Duration(milliseconds: 1200)),
        const Duration(milliseconds: 1500));
    expect(nativeLiveSampleInterval(const Duration(milliseconds: 2200)),
        const Duration(milliseconds: 2500));
    expect(nativeLiveSampleInterval(const Duration(seconds: 12)),
        const Duration(milliseconds: 2500));
  });

  test('invalid durations and backward wall clock fail conservatively', () {
    expect(nativeLiveSampleInterval(const Duration(milliseconds: -1)),
        nativeLiveDefaultSampleInterval);
    expect(nativeLiveSampleDue(
      previousSample: origin,
      now: origin.subtract(const Duration(milliseconds: 1)),
      previousOcrDuration: Duration.zero,
    ), isFalse);
  });
}
