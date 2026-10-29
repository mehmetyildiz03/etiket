import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_yuv420_nv21.dart';

YuvPlaneBytes plane(List<int> values, int rowStride, int pixelStride) =>
    YuvPlaneBytes(Uint8List.fromList(values), rowStride, pixelStride);

void main() {
  test('contiguous YUV420 converts to NV21 with V before U', () {
    final result = yuv420ToNv21(
      width: 4, height: 2,
      y: plane([1, 2, 3, 4, 5, 6, 7, 8], 4, 1),
      u: plane([10, 11], 2, 1),
      v: plane([20, 21], 2, 1),
    );
    expect(result, [1, 2, 3, 4, 5, 6, 7, 8, 20, 10, 21, 11]);
  });

  test('row padding and interleaved chroma pixel stride are respected', () {
    final result = yuv420ToNv21(
      width: 4, height: 4,
      y: plane([
        1, 2, 3, 4, 99, 99,
        5, 6, 7, 8, 99, 99,
        9, 10, 11, 12, 99, 99,
        13, 14, 15, 16, 99, 99,
      ], 6, 1),
      u: plane([30, 0, 31, 0, 99, 99, 32, 0, 33, 0], 6, 2),
      v: plane([40, 0, 41, 0, 99, 99, 42, 0, 43, 0], 6, 2),
    );
    expect(result, [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
      40, 30, 41, 31, 42, 32, 43, 33,
    ]);
  });

  test('Y plane pixel stride is respected', () {
    expect(yuv420ToNv21(
      width: 2, height: 2,
      y: plane([1, 99, 2, 99, 3, 99, 4], 4, 2),
      u: plane([5], 1, 1),
      v: plane([6], 1, 1),
    ), [1, 2, 3, 4, 6, 5]);
  });

  test('invalid or truncated planes fail closed without fabricated bytes', () {
    final y = plane([1, 2, 3, 4], 2, 1);
    final u = plane([5], 1, 1);
    final v = plane([6], 1, 1);
    expect(yuv420ToNv21(width: 2, height: 2,
        y: y, u: u, v: v), [1, 2, 3, 4, 6, 5]);
    expect(yuv420ToNv21(width: 2, height: 2,
        y: y, u: u, v: plane([], 1, 1)), isNull);
    expect(yuv420ToNv21(width: 2, height: 2,
        y: plane([1, 2, 3], 2, 1), u: u, v: v), isNull);
    expect(yuv420ToNv21(width: 2, height: 2,
        y: plane([1, 2, 3, 4], 1, 1), u: u, v: v), isNull);
    expect(yuv420ToNv21(width: 3, height: 2,
        y: y, u: u, v: v), isNull);
    expect(yuv420ToNv21(width: 0, height: 2,
        y: y, u: u, v: v), isNull);
    expect(yuv420ToNv21(width: 4000, height: 4000,
        y: y, u: u, v: v), isNull);
  });
}
