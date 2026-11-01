/// Adaptive sampling of device-local camera OCR. This does not change the
/// recognized text, confidence, readiness, still photo or user approval.
/// Keep one OCR request in flight; pace new samples from the measured cost
/// of the previous completed request rather than a fixed 1.8-second delay.
const nativeLiveDefaultSampleInterval = Duration(milliseconds: 1800);
const nativeLiveMinimumSampleInterval = Duration(milliseconds: 1000);
const nativeLiveMaximumSampleInterval = Duration(milliseconds: 2500);

Duration nativeLiveSampleInterval(Duration? previousOcrDuration) {
  if (previousOcrDuration == null || previousOcrDuration.isNegative) {
    return nativeLiveDefaultSampleInterval;
  }
  // A 25% margin prevents rapid re-sampling when OCR is expensive. The
  // maximum interval bounds the delay before the next useful observation.
  final costMs = previousOcrDuration.inMilliseconds;
  final pacedMs = (costMs * 5 + 3) ~/ 4;
  return Duration(milliseconds: pacedMs
      .clamp(nativeLiveMinimumSampleInterval.inMilliseconds,
          nativeLiveMaximumSampleInterval.inMilliseconds)
      .toInt());
}

bool nativeLiveSampleDue({
  required DateTime previousSample,
  required DateTime now,
  required Duration? previousOcrDuration,
}) {
  final age = now.difference(previousSample);
  return !age.isNegative && age >= nativeLiveSampleInterval(previousOcrDuration);
}
