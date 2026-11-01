import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/live_frame_quality.dart';
import 'package:etiket/scan/native_frame_luminance.dart';
import 'package:etiket/scan/native_pair_pixel_quality.dart';

void main() {
  test('real OCR line pixels override misleading bright center background', () {
    const width = 96, height = 96;
    final pixels = Uint8List(width * height)..fillRange(0, width * height, 245);
    // Small real printed strokes away from the center grid. A whole-scene
    // brightness probe can call this glare even though the OCR line is legible.
    for (var y = 36; y < 60; y++) {
      for (var x = 80; x < 90; x++) {
        pixels[y * width + x] = 10;
      }
    }
    final center = sampleNativeCenterLuminance(
      bytes: pixels, width: width, height: height,
      rowStride: width, pixelStride: 1, bgra: false)!;
    final pair = sampleNativeOcrPairLuminance(
      bytes: pixels, width: width, height: height,
      rowStride: width, pixelStride: 1, bgra: false,
      rotationDegrees: 0,
      normalizedBox: const Rect.fromLTRB(76 / 96, 32 / 96, 94 / 96, 64 / 96),
    )!;
    expect(assessLiveLuminance(center), LiveFrameQuality.glare);
    expect(assessLiveLuminance(pair), LiveFrameQuality.usable);
    expect(pair.length, lessThanOrEqualTo(2304));
  });

  test('all four OCR rotations address the same raw printed pixels', () {
    const size = 64;
    final pixels = Uint8List(size * size)..fillRange(0, size * size, 245);
    for (var y = 16; y < 32; y++) {
      for (var x = 8; x < 24; x++) {
        pixels[y * size + x] = 10;
      }
    }
    const boxes = <int, Rect>{
      0: Rect.fromLTRB(8 / 64, 16 / 64, 24 / 64, 32 / 64),
      90: Rect.fromLTRB(32 / 64, 8 / 64, 48 / 64, 24 / 64),
      180: Rect.fromLTRB(40 / 64, 32 / 64, 56 / 64, 48 / 64),
      270: Rect.fromLTRB(16 / 64, 40 / 64, 32 / 64, 56 / 64),
    };
    for (final entry in boxes.entries) {
      final samples = sampleNativeOcrPairLuminance(
        bytes: pixels, width: size, height: size,
        rowStride: size, pixelStride: 1, bgra: false,
        rotationDegrees: entry.key, normalizedBox: entry.value,
      );
      expect(samples, isNotNull, reason: '${entry.key}°');
      expect(samples, everyElement(10), reason: '${entry.key}°');
    }
  });

  test('BGRA and padded Android Y plane sample visible pixels only', () {
    const width = 64, height = 64;
    final yPlane = Uint8List((width + 8) * height);
    final bgra = Uint8List((width * 4 + 8) * height);
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        final value = (row >= 16 && row < 32 && col >= 8 && col < 24)
            ? 10 : 245;
        yPlane[row * (width + 8) + col] = value;
        final offset = row * (width * 4 + 8) + col * 4;
        bgra[offset] = value;
        bgra[offset + 1] = value;
        bgra[offset + 2] = value;
        bgra[offset + 3] = 255;
      }
    }
    const box = Rect.fromLTRB(4 / 64, 12 / 64, 28 / 64, 36 / 64);
    final android = sampleNativeOcrPairLuminance(
      bytes: yPlane, width: width, height: height,
      rowStride: width + 8, pixelStride: 1, bgra: false,
      rotationDegrees: 0, normalizedBox: box,
    );
    final iosPixels = sampleNativeOcrPairLuminance(
      bytes: bgra, width: width, height: height,
      rowStride: width * 4 + 8, pixelStride: 4, bgra: true,
      rotationDegrees: 0, normalizedBox: box,
    );
    expect(android, isNotNull);
    expect(iosPixels, android);
    expect(assessLiveLuminance(android!), LiveFrameQuality.usable);
  });

  test('malformed OCR coordinates, unsupported rotation and tiny ROI fail closed', () {
    const width = 64, height = 64;
    final pixels = Uint8List(width * height);
    Uint8List? sample(Rect box, {int rotation = 0, int stride = width}) =>
        sampleNativeOcrPairLuminance(
          bytes: pixels, width: width, height: height,
          rowStride: stride, pixelStride: 1, bgra: false,
          rotationDegrees: rotation, normalizedBox: box,
        );
    expect(sample(const Rect.fromLTRB(-.01, .2, .5, .5)), isNull);
    expect(sample(const Rect.fromLTRB(.2, .2, 1.01, .5)), isNull);
    expect(sample(const Rect.fromLTRB(.2, .2, .2, .5)), isNull);
    expect(sample(const Rect.fromLTRB(.2, .2, .5, .5), rotation: 45), isNull);
    expect(sample(const Rect.fromLTRB(.2, .2, .5, .5), stride: 1), isNull);
    expect(sample(const Rect.fromLTRB(.2, .2, .21, .21)), isNull);
  });
}
