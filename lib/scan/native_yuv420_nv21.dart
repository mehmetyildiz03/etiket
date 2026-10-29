import 'dart:typed_data';

/// A plane with explicit Android YUV_420_888 row/pixel strides.
/// Used only for transient camera-frame conversion; never persisted.
class YuvPlaneBytes {
  const YuvPlaneBytes(this.bytes, this.rowStride, this.pixelStride);

  final Uint8List bytes;
  final int rowStride;
  final int pixelStride;
}

/// ML Kit's Flutter byte bridge accepts NV21, not three separate YUV planes.
/// Convert CameraX's possible 3-plane YUV_420_888 output to tightly packed NV21
/// (Y followed by V,U interleaved), respecting row padding and pixel strides.
/// Invalid/truncated/oversized frames fail closed so the system camera remains
/// available; no image bytes are logged, uploaded, or retained.
Uint8List? yuv420ToNv21({
  required int width,
  required int height,
  required YuvPlaneBytes y,
  required YuvPlaneBytes u,
  required YuvPlaneBytes v,
}) {
  if (width <= 0 || height <= 0 || width.isOdd || height.isOdd ||
      width * height > 12000000) {
    return null;
  }
  final chromaWidth = width ~/ 2;
  final chromaHeight = height ~/ 2;

  bool valid(YuvPlaneBytes plane, int columns, int rows) {
    if (plane.rowStride <= 0 || plane.pixelStride <= 0 ||
        plane.rowStride < (columns - 1) * plane.pixelStride + 1) {
      return false;
    }
    final last = (rows - 1) * plane.rowStride +
        (columns - 1) * plane.pixelStride;
    return last >= 0 && last < plane.bytes.length;
  }

  if (!valid(y, width, height) ||
      !valid(u, chromaWidth, chromaHeight) ||
      !valid(v, chromaWidth, chromaHeight)) {
    return null;
  }
  final pixelCount = width * height;
  final nv21 = Uint8List(pixelCount + pixelCount ~/ 2);
  var offset = 0;
  for (var row = 0; row < height; row++) {
    final base = row * y.rowStride;
    for (var column = 0; column < width; column++) {
      nv21[offset++] = y.bytes[base + column * y.pixelStride];
    }
  }
  for (var row = 0; row < chromaHeight; row++) {
    final uBase = row * u.rowStride;
    final vBase = row * v.rowStride;
    for (var column = 0; column < chromaWidth; column++) {
      nv21[offset++] = v.bytes[vBase + column * v.pixelStride];
      nv21[offset++] = u.bytes[uBase + column * u.pixelStride];
    }
  }
  return nv21;
}
