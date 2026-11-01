/// Explicit, device-local torch control for live label reading. A successful
/// hardware request only changes illumination, never validates OCR or a label.
/// No camera frame, raw OCR, EXIF or user data is recorded or uploaded.
enum NativeTorchStatus { changed, unavailable }

class NativeTorchOutcome {
  const NativeTorchOutcome(this.status, this.enabled);

  final NativeTorchStatus status;
  final bool enabled;
}

/// Never show the requested light state before the hardware call succeeds.
/// Unsupported flash hardware and camera lifecycle failures fail closed.
Future<NativeTorchOutcome> changeNativeCameraTorch({
  required bool currentlyEnabled,
  required Future<void> Function(bool enabled) setTorchEnabled,
}) async {
  final target = !currentlyEnabled;
  try {
    await setTorchEnabled(target);
    return NativeTorchOutcome(NativeTorchStatus.changed, target);
  } catch (_) {
    return NativeTorchOutcome(
      NativeTorchStatus.unavailable, currentlyEnabled);
  }
}
