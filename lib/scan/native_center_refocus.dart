import 'dart:ui';

/// Request hardware autofocus and metering at a normalized preview point.
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

/// Convert a tap within the *displayed preview* to a bounded CameraController
/// focus/exposure point. A tap outside the preview must never steer hardware.
/// The center button remains the accessible fallback for unsupported devices.
Offset? nativePreviewTapPoint(Offset local, Size viewport) {
  if (!local.dx.isFinite || !local.dy.isFinite ||
      !viewport.width.isFinite || !viewport.height.isFinite ||
      viewport.width <= 0 || viewport.height <= 0 ||
      local.dx < 0 || local.dy < 0 ||
      local.dx > viewport.width || local.dy > viewport.height) {
    return null;
  }
  return Offset(
    (local.dx / viewport.width).clamp(0.05, 0.95).toDouble(),
    (local.dy / viewport.height).clamp(0.05, 0.95).toDouble(),
  );
}

Future<NativeCenterRefocusResult> requestNativeCenterRefocus({
  Offset point = const Offset(0.5, 0.5),
  required Future<void> Function(Offset) setFocusPoint,
  required Future<void> Function(Offset) setExposurePoint,
}) async {
  if (!point.dx.isFinite || !point.dy.isFinite ||
      point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1) {
    return NativeCenterRefocusResult.unavailable;
  }
  var focusRequested = false;
  var exposureRequested = false;
  try {
    await setFocusPoint(point);
    focusRequested = true;
  } catch (_) {
    // Hardware/OS may reject point focus. Try exposure independently.
  }
  try {
    await setExposurePoint(point);
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
