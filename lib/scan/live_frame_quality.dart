import 'dart:typed_data';

enum LiveFrameQuality { dark, glare, lowDetail, usable, unknown }

/// A bounded, ephemeral luminance probe. This is camera guidance, NOT OCR
/// confidence or a calibrated focus measurement. No image bytes are retained.
LiveFrameQuality assessLiveLuminance(Uint8List samples) {
  if (samples.length < 16) return LiveFrameQuality.unknown;
  var total = 0;
  final histogram = List<int>.filled(256, 0);
  for (final value in samples) {
    total += value;
    histogram[value]++;
  }
  final mean = total / samples.length;

  // A white care label can have mean > 218 while its small dark letters are
  // legible; likewise for bright lettering on dark fabric. Mean alone must
  // not trigger a misleading light warning or reset candidate stability.
  // Ignore isolated hot/dead pixels by measuring the central 90% of values.
  int percentile(int rank) {
    var count = 0;
    for (var value = 0; value < histogram.length; value++) {
      count += histogram[value];
      if (count > rank) return value;
    }
    return 255;
  }

  final tail = (samples.length - 1) ~/ 20;
  final contrast = percentile(samples.length - 1 - tail) - percentile(tail);
  if (mean < 48 && contrast <= 20) return LiveFrameQuality.dark;
  if (mean > 218 && contrast <= 20) return LiveFrameQuality.glare;
  if (contrast < 20) return LiveFrameQuality.lowDetail;
  // Contrast is only an exposure clue, not focus or OCR correctness.
  return LiveFrameQuality.usable;
}

String liveQualityAdvice(LiveFrameQuality quality) => switch (quality) {
  LiveFrameQuality.dark => 'Işığı artır veya etiketi aydınlığa çevir.',
  LiveFrameQuality.glare => 'Parlamayı azalt; kameranın açısını değiştir.',
  LiveFrameQuality.lowDetail => 'Etikete yaklaş, sabitle ve odakla.',
  LiveFrameQuality.usable || LiveFrameQuality.unknown =>
    'Tüm etiketi kadraja al, kamerayı sabit tut.',
};
