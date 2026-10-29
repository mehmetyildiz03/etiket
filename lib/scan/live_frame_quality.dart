import 'dart:typed_data';

enum LiveFrameQuality { dark, glare, lowDetail, usable, unknown }

/// A bounded, ephemeral luminance probe. This is camera guidance, NOT OCR
/// confidence or a calibrated focus measurement. No image bytes are retained.
LiveFrameQuality assessLiveLuminance(Uint8List samples) {
  if (samples.length < 16) return LiveFrameQuality.unknown;
  var total = 0, low = 255, high = 0;
  for (final value in samples) {
    total += value;
    if (value < low) low = value;
    if (value > high) high = value;
  }
  final mean = total / samples.length;
  if (mean < 48) return LiveFrameQuality.dark;
  if (mean > 218) return LiveFrameQuality.glare;
  if (high - low < 20) return LiveFrameQuality.lowDetail;
  return LiveFrameQuality.usable;
}

String liveQualityAdvice(LiveFrameQuality quality) => switch (quality) {
  LiveFrameQuality.dark => 'Işığı artır veya etiketi aydınlığa çevir.',
  LiveFrameQuality.glare => 'Parlamayı azalt; kameranın açısını değiştir.',
  LiveFrameQuality.lowDetail => 'Etikete yaklaş, sabitle ve odakla.',
  LiveFrameQuality.usable || LiveFrameQuality.unknown =>
    'Tüm etiketi kadraja al, kamerayı sabit tut.',
};
