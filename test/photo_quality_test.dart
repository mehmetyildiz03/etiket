import 'dart:typed_data';

import 'package:etiket/scan/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List grayRgba(List<int> luma, {int alpha = 255}) {
  final rgba = Uint8List(luma.length * 4);
  for (var i = 0; i < luma.length; i++) {
    rgba.setRange(i * 4, i * 4 + 4, [
      luma[i],
      luma[i],
      luma[i],
      alpha,
    ]);
  }
  return rgba;
}

void main() {
  test('uniform midtone gives a low-detail hint, not an exposure warning', () {
    final report = PhotoQualityReport.fromRgba(
      rgba: grayRgba(List.filled(16, 128)),
      width: 4,
      height: 4,
    );
    expect(report.dynamicRange, 0);
    expect(report.meanLuma, 128);
    expect(report.meanNeighborDifference, 0);
    expect(report.possiblyLowContrast, isTrue);
    expect(report.possiblyLowDetail, isTrue);
    expect(report.possiblyTooDark, isFalse);
    expect(report.possiblyTooBright, isFalse);
  });

  test('high-frequency synthetic pattern is not marked as low detail', () {
    final pixels = List.generate(
      16,
      (i) => ((i ~/ 4 + i % 4).isEven) ? 0 : 255,
    );
    final report = PhotoQualityReport.fromRgba(
      rgba: grayRgba(pixels),
      width: 4,
      height: 4,
    );
    expect(report.dynamicRange, 255);
    expect(report.meanNeighborDifference, 255);
    expect(report.darkClippingFraction, .5);
    expect(report.lightClippingFraction, .5);
    expect(report.possiblyLowContrast, isFalse);
    expect(report.possiblyLowDetail, isFalse);
    expect(report.possiblyTooDark, isFalse);
    expect(report.possiblyTooBright, isFalse);
  });

  test('exposure hints require both clipped pixels and extreme mean', () {
    final dark = PhotoQualityReport.fromRgba(
      rgba: grayRgba(List.filled(16, 0)),
      width: 4,
      height: 4,
    );
    final bright = PhotoQualityReport.fromRgba(
      rgba: grayRgba(List.filled(16, 255)),
      width: 4,
      height: 4,
    );
    expect(dark.possiblyTooDark, isTrue);
    expect(dark.possiblyTooBright, isFalse);
    expect(bright.possiblyTooBright, isTrue);
    expect(bright.possiblyTooDark, isFalse);
  });

  test('transparent pixels are composited over white, not black', () {
    final report = PhotoQualityReport.fromRgba(
      rgba: grayRgba([0, 0, 0, 0], alpha: 0),
      width: 2,
      height: 2,
    );
    expect(report.meanLuma, 255);
    expect(report.lightClippingFraction, 1);
    expect(report.possiblyTooBright, isTrue);
  });

  test('invalid dimensions, truncated bytes and huge inputs fail closed', () {
    expect(
      () => PhotoQualityReport.fromRgba(
        rgba: Uint8List(0),
        width: 0,
        height: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => PhotoQualityReport.fromRgba(
        rgba: Uint8List(15),
        width: 2,
        height: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => PhotoQualityReport.fromRgba(
        rgba: Uint8List(0),
        width: 257,
        height: 2,
      ),
      throwsArgumentError,
    );
  });

  test('analysis does not modify caller-owned pixel bytes', () {
    final bytes = grayRgba([0, 64, 128, 255]);
    final before = Uint8List.fromList(bytes);
    PhotoQualityReport.fromRgba(rgba: bytes, width: 2, height: 2);
    expect(bytes, orderedEquals(before));
  });
}
