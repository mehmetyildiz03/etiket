/// Runs a full-resolution still capture after pausing preview frames.
/// If stopping or taking the still fails, attempt to restore the live stream
/// so the user can retry without leaving the camera. Never logs camera data.
class NativeStillOutcome<T> {
  const NativeStillOutcome._(this.photo, this.streamRecovered);

  final T? photo;
  final bool streamRecovered;
}

Future<NativeStillOutcome<T>> takeNativeStillWithRecovery<T>({
  required Future<void> Function() stopPreview,
  required Future<T> Function() takeStill,
  required Future<void> Function() resumePreview,
}) async {
  try {
    await stopPreview();
    final photo = await takeStill();
    return NativeStillOutcome._(photo, false);
  } catch (_) {
    var recovered = false;
    try {
      await resumePreview();
      recovered = true;
    } catch (_) {
      // A closed or unavailable camera must fall back to the system picker.
    }
    return NativeStillOutcome._(null, recovered);
  }
}
