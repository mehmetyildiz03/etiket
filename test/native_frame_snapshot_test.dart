import 'dart:typed_data';
import 'dart:ui';

import 'package:etiket/scan/live_frame_quality.dart';
import 'package:etiket/scan/native_frame_snapshot.dart';
import 'package:etiket/scan/native_pair_pixel_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('async OCR cannot measure a later recycled frame for ROI exposure', () {
    const width = 64, height = 64;
    final cameraBuffer = Uint8List(width * height)
      ..fillRange(0, width * height, 12);
    final frozen = snapshotNativeLumaPlane(
      bytes: cameraBuffer, width: width, height: height,
      rowStride: width, pixelStride: 1,
    );
    expect(frozen, isNotNull);
    expect(identical(frozen, cameraBuffer), isFalse);

    // Simulate the camera plugin reusing its buffer while ML Kit awaits.
    cameraBuffer.fillRange(0, width * height, 245);
    LiveFrameQuality quality(Uint8List bytes) =>
        assessNativeMatchedPairQuality(
          bytes: bytes, width: width, height: height,
          rowStride: width, pixelStride: 1, bgra: false,
          rotationDegrees: 0,
          normalizedBoxes: const [Rect.fromLTRB(.2, .2, .8, .8)],
        );
    expect(quality(frozen!), LiveFrameQuality.dark);
    expect(quality(cameraBuffer), LiveFrameQuality.glare);
  });

  test('padded and pixel-strided camera planes pack only actual Y pixels', () {
    final cameraBuffer = Uint8List(24)..fillRange(0, 24, 255);
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 4; column++) {
        cameraBuffer[row * 8 + column * 2] = 10 + row * 4 + column;
      }
    }
    final frozen = snapshotNativeLumaPlane(
      bytes: cameraBuffer, width: 4, height: 3,
      rowStride: 8, pixelStride: 2,
    );
    expect(frozen, isNotNull);
    expect(frozen, hasLength(12)); // Not 23 bytes of padded camera data.
    expect(frozen, orderedEquals(List<int>.generate(12, (i) => i + 10)));
    cameraBuffer[22] = 99;
    expect(frozen![11], 21);
  });

  test('rotated OCR ROI reads compact Y, not bright padding', () {
    const width = 64, height = 64, stride = 160;
    final source = Uint8List(stride * height)
      ..fillRange(0, stride * height, 245);
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        source[row * stride + col * 2] = 12;
      }
    }
    final frozen = snapshotNativeLumaPlane(
      bytes: source, width: width, height: height,
      rowStride: stride, pixelStride: 2,
    );
    expect(frozen, hasLength(width * height));
    LiveFrameQuality measure(Uint8List bytes, int rowStride, int pixelStride) =>
        assessNativeMatchedPairQuality(
          bytes: bytes, width: width, height: height,
          rowStride: rowStride, pixelStride: pixelStride,
          bgra: false, rotationDegrees: 90,
          normalizedBoxes: const [Rect.fromLTRB(.2, .2, .8, .8)],
        );
    expect(measure(source, stride, 2), LiveFrameQuality.dark);
    expect(measure(frozen!, width, 1), LiveFrameQuality.dark);
    source.fillRange(0, source.length, 245);
    expect(measure(frozen, width, 1), LiveFrameQuality.dark);
  });

  test('source padding over 16 MiB does not inflate frozen frame', () {
    const stride = 9 * 1024 * 1024;
    final source = Uint8List(stride * 2 + 4);
    source[0] = 11;
    source[stride] = 22;
    source[2 * stride] = 33;
    final frozen = snapshotNativeLumaPlane(
      bytes: source, width: 4, height: 3,
      rowStride: stride, pixelStride: 1,
    );
    expect(frozen, hasLength(12));
    expect(frozen![0], 11);
    expect(frozen[4], 22);
    expect(frozen[8], 33);
  });

  test('truncated, malformed and oversized planes fail closed', () {
    Uint8List? snapshot({
      required Uint8List bytes, required int width,
      required int height, required int stride, int pixelStride = 1,
    }) => snapshotNativeLumaPlane(
      bytes: bytes, width: width, height: height,
      rowStride: stride, pixelStride: pixelStride,
    );
    expect(snapshot(bytes: Uint8List(63), width: 8, height: 8,
        stride: 8), isNull);
    expect(snapshot(bytes: Uint8List(64), width: 8, height: 8,
        stride: 7), isNull);
    expect(snapshot(bytes: Uint8List(64), width: 8, height: 8,
        stride: 8, pixelStride: 2), isNull);
    expect(snapshot(bytes: Uint8List(1), width: 4000, height: 3001,
        stride: 4000), isNull);
    expect(snapshot(bytes: Uint8List(1), width: 1, height: 1,
        stride: 16 * 1024 * 1024 + 1), isNotNull);
    expect(snapshot(bytes: Uint8List(1), width: 2, height: 2,
        stride: 16 * 1024 * 1024 + 1), isNull);
  });
}
