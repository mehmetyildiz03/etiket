/// User-triggered optical/digital camera hardware zoom for live label OCR.
/// A successful request changes the field of view, NOT OCR correctness.
/// No frame, text, metadata, or camera identifier is retained or uploaded.
enum NativeZoomStatus { changed, unchanged, unavailable }

class NativeZoomOutcome {
  const NativeZoomOutcome(this.status, this.zoom);

  final NativeZoomStatus status;
  final double zoom;
}

/// Query actual camera capabilities on each request. Do not guess a zoom
/// range, and never report a zoom change if the platform rejects the request.
Future<NativeZoomOutcome> changeNativeCameraZoom({
  required double current,
  required bool zoomIn,
  required Future<double> Function() getMinZoomLevel,
  required Future<double> Function() getMaxZoomLevel,
  required Future<void> Function(double) setZoomLevel,
}) async {
  if (!current.isFinite || current <= 0) {
    return NativeZoomOutcome(NativeZoomStatus.unavailable, current);
  }
  try {
    final min = await getMinZoomLevel();
    final max = await getMaxZoomLevel();
    if (!min.isFinite || !max.isFinite || min <= 0 || max < min) {
      return NativeZoomOutcome(NativeZoomStatus.unavailable, current);
    }
    final from = current.clamp(min, max).toDouble();
    final target = (zoomIn ? from * 1.5 : from / 1.5)
        .clamp(min, max).toDouble();
    if ((target - from).abs() < 0.005) {
      return NativeZoomOutcome(NativeZoomStatus.unchanged, from);
    }
    await setZoomLevel(target);
    return NativeZoomOutcome(NativeZoomStatus.changed, target);
  } catch (_) {
    // Unsupported, detached, or paused camera: leave the last known zoom.
    return NativeZoomOutcome(NativeZoomStatus.unavailable, current);
  }
}
