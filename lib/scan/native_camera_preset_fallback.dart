import 'package:camera/camera.dart';

/// The camera plugin may apply the STREAM resolution preset to takePicture().
/// A fallback preview must not silently become the final OCR still.
bool nativeStreamRequiresSystemStill(ResolutionPreset preset) =>
    preset != ResolutionPreset.ultraHigh;

/// Try a lower stream resolution only when the camera cannot initialize or
/// start streaming at ultraHigh. This is about live camera availability, not
/// OCR confidence. The full-resolution still is taken separately by the
/// camera plugin after the preview stream stops.
Future<T> openNativeCameraWithPresetFallback<T>({
  required T Function(ResolutionPreset preset) create,
  required Future<void> Function(T controller) initializeAndStart,
  required Future<void> Function(T controller) dispose,
  required bool Function() cancelled,
}) async {
  Object? lastError;
  StackTrace? lastStack;
  for (final preset in const [ResolutionPreset.ultraHigh, ResolutionPreset.high]) {
    if (cancelled()) throw StateError('camera start cancelled');
    final candidate = create(preset);
    try {
      await initializeAndStart(candidate);
      if (cancelled()) throw StateError('camera start cancelled');
      return candidate;
    } catch (error, stack) {
      // A failed startImageStream may still own camera resources. Release the
      // entire attempt before creating the next controller.
      try {
        await dispose(candidate);
      } catch (cleanupError, cleanupStack) {
        // A camera that could not be released may still own the device.
        // Do not start another controller on top of a possibly live stream.
        Error.throwWithStackTrace(cleanupError, cleanupStack);
      }
      // Lifecycle pause/dispose is NOT a reason to open another camera.
      if (cancelled()) Error.throwWithStackTrace(error, stack);
      lastError = error;
      lastStack = stack;
    }
  }
  Error.throwWithStackTrace(lastError!, lastStack!);
}
