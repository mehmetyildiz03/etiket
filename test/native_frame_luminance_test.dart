import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/native_frame_luminance.dart';
import 'package:etiket/scan/live_frame_quality.dart';

void main() {
  test('padded YUV rows are not sampled as darkness or glare', () {
    final bytes = Uint8List.fromList([
      80, 80, 80, 80, 255, 255,
      80, 80, 80, 80, 255, 255,
      80, 80, 80, 80,
    ]);
    final samples = sampleNativeLuminance(
      bytes: bytes, width: 4, height: 3,
      rowStride: 6, pixelStride: 1, bgra: false);
    expect(samples, everyElement(80));
  });

  test('Y plane pixel stride excludes padding bytes', () {
    final samples = sampleNativeLuminance(
      bytes: Uint8List.fromList([90, 0, 91, 0, 92, 0, 93]),
      width: 2, height: 2, rowStride: 4, pixelStride: 2, bgra: false);
    expect(samples, [90, 91, 92, 93]);
  });

  test('iOS BGRA uses visible channels with row padding', () {
    final samples = sampleNativeLuminance(
      bytes: Uint8List.fromList([
        0, 0, 255, 255, 0, 255, 0, 255, 99, 99,
        255, 0, 0, 255, 255, 255, 255, 255,
      ]),
      width: 2, height: 2, rowStride: 10, pixelStride: 4, bgra: true);
    expect(samples, [76, 150, 29, 255]);
  });

  test('truncated or contradictory planes are unknown, not invented', () {
    Uint8List? read(int stride, int pixelStride, List<int> bytes) =>
      sampleNativeLuminance(bytes: Uint8List.fromList(bytes),
        width: 2, height: 2, rowStride: stride,
        pixelStride: pixelStride, bgra: false);
    expect(read(2, 1, [80, 80, 80]), isNull);
    expect(read(1, 1, [80, 80, 80, 80]), isNull);
    expect(read(2, 0, [80, 80, 80, 80]), isNull);
    expect(assessLiveLuminance(read(2, 1, [80, 80, 80, 80])!),
        LiveFrameQuality.unknown);
  });

  test('bounded sampling covers the full frame without keeping it', () {
    final samples = sampleNativeLuminance(
      bytes: Uint8List(1024 * 1024), width: 1024, height: 1024,
      rowStride: 1024, pixelStride: 1, bgra: false);
    expect(samples, hasLength(512));
  });

  test('thin printed strokes in camera guide are not falsely called glare', () {
    // Bright label with narrow dark glyph strokes between 16x16 probe points.
    // Test actual YUV luminance and iOS BGRA camera byte layouts, not OCR.
    const width = 96, height = 96;
    final y = Uint8List(width * height)..fillRange(0, width * height, 245);
    final bgra = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      bgra[i * 4] = 245;
      bgra[i * 4 + 1] = 245;
      bgra[i * 4 + 2] = 245;
      bgra[i * 4 + 3] = 255;
    }
    for (var row = 24; row < 72; row++) {
      for (final column in [22, 26, 30, 34]) {
        y[row * width + column] = 10;
        final offset = (row * width + column) * 4;
        bgra[offset] = 10;
        bgra[offset + 1] = 10;
        bgra[offset + 2] = 10;
      }
    }
    final android = sampleNativeCenterLuminance(
      bytes: y, width: width, height: height,
      rowStride: width, pixelStride: 1, bgra: false);
    final ios = sampleNativeCenterLuminance(
      bytes: bgra, width: width, height: height,
      rowStride: width * 4, pixelStride: 4, bgra: true);
    expect(android, hasLength(2304));
    expect(ios, android);
    expect(assessLiveLuminance(android!), LiveFrameQuality.usable);
    expect(assessLiveLuminance(ios!), LiveFrameQuality.usable);
  });

}
