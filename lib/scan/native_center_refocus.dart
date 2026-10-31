import 'dart:ui';

/// Request hardware autofocus and metering at the center of the preview.
///
/// This is a user-triggered camera operation, not proof of sharpness or OCR
/// correctness. Some Android/iOS devices support only one of the operations.
/// Fail independently so an unsupported exposure point cannot disable focus.
/// No frame, text, location or camera metadata is recorded.
enum NativeCenterRefocusResult {
  focusAndExposureRequested,
  focusOnlyRequested,
  exposureOnlyRequested,
  unavailable,
}

Future<NativeCenterRefocusResult> requestNativeCenterRefocus({
  required Future<void> Function(Offset) setFocusPoint,
  required Future<void> Function(Offset) setExposurePoint,
}) async {
  const center = Offset(0.5, 0.5);
  var focusRequested = false;
  var exposureRequested = false;
  try {
    await setFocusPoint(center);
    focusRequested = true;
  } catch (_) {
    // Hardware/OS may reject point focus. Try exposure independently.
  }
  try {
    await setExposurePoint(center);
    exposureRequested = true;
  } catch (_) {
    // No hardware metering support is a recoverable camera condition.
  }
  if (focusRequested && exposureRequested) {
    return NativeCenterRefocusResult.focusAndExposureRequested;
  }
  if (focusRequested) return NativeCenterRefocusResult.focusOnlyRequested;
  if (exposureRequested) return NativeCenterRefocusResult.exposureOnlyRequested;
  return NativeCenterRefocusResult.unavailable;
}
