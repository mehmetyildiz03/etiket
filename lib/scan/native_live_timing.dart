/// Temporal limits for *advisory* native live OCR. A result describes the
/// camera pixels sampled before ML Kit ran, not the time its callback returned.
/// No raw frames, OCR text, or device identifiers are retained here.
const nativeLiveHintMaxAge = Duration(seconds: 6);
const nativeLiveStabilityMaxGap = Duration(seconds: 5);

bool nativeLiveHintFresh(DateTime sampledAt, DateTime checkedAt) {
  final age = checkedAt.difference(sampledAt);
  return !age.isNegative && age < nativeLiveHintMaxAge;
}

/// Stability is about the interval between two independently sampled frames,
/// not the interval between two potentially slow OCR completions.
bool nativeLiveSamplesWithinGap(DateTime previousSample,
    DateTime currentSample) {
  final gap = currentSample.difference(previousSample);
  return !gap.isNegative && gap <= nativeLiveStabilityMaxGap;
}
