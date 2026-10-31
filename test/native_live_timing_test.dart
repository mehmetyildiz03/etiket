import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_live_timing.dart';

void main() {
  final origin = DateTime.utc(2026, 10, 31);

  test('slow native OCR keeps only the remaining sampled-frame lifetime', () {
    final sampled = origin;
    expect(nativeLiveHintFresh(sampled,
        origin.add(const Duration(milliseconds: 5500))), isTrue);
    expect(nativeLiveHintFresh(sampled,
        origin.add(const Duration(milliseconds: 5999))), isTrue);
    expect(nativeLiveHintFresh(sampled,
        origin.add(const Duration(seconds: 6))), isFalse);
    expect(nativeLiveHintFresh(sampled,
        origin.add(const Duration(milliseconds: 6001))), isFalse);
  });

  test('future sample timestamps fail closed after clock changes', () {
    expect(nativeLiveHintFresh(origin.add(const Duration(seconds: 1)),
        origin), isFalse);
  });

  test('native stability compares capture times, not completion times', () {
    final first = origin;
    final second = origin.add(const Duration(milliseconds: 5200));
    // Callbacks only 300ms apart do not establish a valid 5-second streak.
    expect(nativeLiveSamplesWithinGap(first, second), isFalse);
    expect(nativeLiveSamplesWithinGap(first,
        origin.add(const Duration(seconds: 5))), isTrue);
    expect(nativeLiveSamplesWithinGap(second, first), isFalse);
  });
}
