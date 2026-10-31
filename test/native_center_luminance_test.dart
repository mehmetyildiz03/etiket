import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/live_frame_quality.dart';
import 'package:etiket/scan/native_frame_luminance.dart';

void main() {
  const width = 40, height = 40, stride = 48;

  Uint8List yPlane(int Function(int x, int y) luminance) {
    final bytes = Uint8List(stride * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        bytes[y * stride + x] = luminance(x, y);
      }
      for (var x = width; x < stride; x++) {
        bytes[y * stride + x] = 255; // Deliberately bright padding.
      }
    }
    return bytes;
  }

  Uint8List? center(Uint8List bytes) => sampleNativeCenterLuminance(
    bytes: bytes, width: width, height: height,
    rowStride: stride, pixelStride: 1, bgra: false,
  );

  test('bright surroundings cannot hide a dark central label area', () {
    final bytes = yPlane((x, y) =>
        x >= 8 && x < 32 && y >= 8 && y < 32 ? 28 : 245);
    expect(assessLiveLuminance(center(bytes)!),
        LiveFrameQuality.dark);
    expect(assessLiveLuminance(sampleNativeLuminance(
      bytes: bytes, width: width, height: height,
      rowStride: stride, pixelStride: 1, bgra: false,
    )!), isNot(LiveFrameQuality.dark));
  });

  test('dark surroundings cannot hide glare in central guide area', () {
    final bytes = yPlane((x, y) =>
        x >= 8 && x < 32 && y >= 8 && y < 32 ? 246 : 15);
    expect(assessLiveLuminance(center(bytes)!),
        LiveFrameQuality.glare);
  });

  test('central visible detail remains usable, padding is never sampled', () {
    final bytes = yPlane((x, y) => x.isEven ? 70 : 170);
    final samples = center(bytes)!;
    expect(samples, hasLength(256));
    expect(samples, everyElement(inInclusiveRange(70, 170)));
    expect(assessLiveLuminance(samples), LiveFrameQuality.usable);
  });

  test('BGRA row padding and channels are respected in central region', () {
    const rowStride = 164;
    final bytes = Uint8List(rowStride * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = y * rowStride + x * 4;
        final value = x >= 8 && x < 32 && y >= 8 && y < 32 ? 25 : 240;
        bytes[offset] = value;
        bytes[offset + 1] = value;
        bytes[offset + 2] = value;
        bytes[offset + 3] = 255;
      }
      for (var x = width * 4; x < rowStride; x++) {
        bytes[y * rowStride + x] = 255;
      }
    }
    final samples = sampleNativeCenterLuminance(
      bytes: bytes, width: width, height: height,
      rowStride: rowStride, pixelStride: 4, bgra: true,
    );
    expect(samples, hasLength(256));
    expect(samples, everyElement(25));
  });

  test('malformed planes fail closed; probe never retains whole frame', () {
    expect(center(Uint8List(100)), isNull);
    expect(sampleNativeCenterLuminance(
      bytes: Uint8List(1600), width: width, height: height,
      rowStride: 20, pixelStride: 1, bgra: false,
    ), isNull);
    expect(sampleNativeCenterLuminance(
      bytes: Uint8List(1600), width: width, height: height,
      rowStride: 40, pixelStride: 0, bgra: false,
    ), isNull);
    expect(sampleNativeCenterLuminance(
      bytes: Uint8List(100), width: 10, height: 10,
      rowStride: 10, pixelStride: 1, bgra: false,
    ), isNull);
    expect(sampleNativeCenterLuminance(
      bytes: Uint8List(1024 * 1024), width: 1024, height: 1024,
      rowStride: 1024, pixelStride: 1, bgra: false,
    ), hasLength(2304));
  });
}
