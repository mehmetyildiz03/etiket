import 'dart:typed_data';

/// Bounded, local-only measurements of a small RGBA thumbnail.
///
/// This is a diagnostic building block, NOT an OCR accuracy score or a blur
/// detector. The caller must downscale the image to at most 256 x 256 pixels.
/// No pixels, EXIF, OCR text or image identifiers are retained.
class PhotoQualityReport {
  const PhotoQualityReport._({
    required this.dynamicRange,
    required this.meanLuma,
    required this.meanNeighborDifference,
    required this.darkClippingFraction,
    required this.lightClippingFraction,
  });

  /// Difference between the 90th and 10th luminance percentiles (0..255).
  final int dynamicRange;

  /// Average luminance after compositing transparent pixels over white.
  final double meanLuma;

  /// Mean absolute difference between adjacent pixels (0..255).
  ///
  /// Low values can reflect plain backgrounds, small text or loss of detail;
  /// they do not establish that the camera was out of focus.
  final double meanNeighborDifference;

  final double darkClippingFraction;
  final double lightClippingFraction;

  /// Uncalibrated hints only; never block OCR or auto-select a variant.
  bool get possiblyLowContrast => dynamicRange < 40;
  bool get possiblyLowDetail => meanNeighborDifference < 8;
  bool get possiblyTooDark =>
      meanLuma < 45 && darkClippingFraction > 0.6;
  bool get possiblyTooBright =>
      meanLuma > 210 && lightClippingFraction > 0.6;

  static PhotoQualityReport fromRgba({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    if (width < 2 ||
        height < 2 ||
        width > 256 ||
        height > 256 ||
        rgba.length != width * height * 4) {
      throw ArgumentError(
        'Expected an RGBA thumbnail between 2x2 and 256x256 pixels.',
      );
    }

    final histogram = List<int>.filled(256, 0);
    final rowAbove = Uint8List(width);
    var sumLuma = 0;
    var sumNeighborDifference = 0;
    var neighborPairs = 0;
    var darkClipped = 0;
    var lightClipped = 0;

    for (var y = 0; y < height; y++) {
      var left = 0;
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final alpha = rgba[offset + 3];
        final white = 255 * (255 - alpha);
        final r = (rgba[offset] * alpha + white + 127) ~/ 255;
        final g = (rgba[offset + 1] * alpha + white + 127) ~/ 255;
        final b = (rgba[offset + 2] * alpha + white + 127) ~/ 255;
        final luma = (299 * r + 587 * g + 114 * b + 500) ~/ 1000;

        histogram[luma]++;
        sumLuma += luma;
        if (luma <= 8) darkClipped++;
        if (luma >= 247) lightClipped++;
        if (x > 0) {
          sumNeighborDifference += (luma - left).abs();
          neighborPairs++;
        }
        if (y > 0) {
          sumNeighborDifference += (luma - rowAbove[x]).abs();
          neighborPairs++;
        }
        rowAbove[x] = luma;
        left = luma;
      }
    }

    final count = width * height;
    int percentile(double fraction) {
      final rank = ((count - 1) * fraction).round();
      var seen = 0;
      for (var i = 0; i < histogram.length; i++) {
        seen += histogram[i];
        if (seen > rank) return i;
      }
      return 255;
    }

    return PhotoQualityReport._(
      dynamicRange: percentile(.9) - percentile(.1),
      meanLuma: sumLuma / count,
      meanNeighborDifference: sumNeighborDifference / neighborPairs,
      darkClippingFraction: darkClipped / count,
      lightClippingFraction: lightClipped / count,
    );
  }
}
