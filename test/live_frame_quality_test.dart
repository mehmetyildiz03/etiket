import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/scan/live_frame_quality.dart';

void main() {
  test('luminance hints are bounded and never OCR correctness', () {
    expect(assessLiveLuminance(Uint8List(8)), LiveFrameQuality.unknown);
    expect(assessLiveLuminance(Uint8List(64)..fillRange(0, 64, 18)),
        LiveFrameQuality.dark);
    expect(assessLiveLuminance(Uint8List(64)..fillRange(0, 64, 240)),
        LiveFrameQuality.glare);
    expect(assessLiveLuminance(Uint8List(64)..fillRange(0, 64, 120)),
        LiveFrameQuality.lowDetail);
    final contrast = Uint8List.fromList(
      List.generate(64, (i) => i.isEven ? 65 : 185));
    expect(assessLiveLuminance(contrast), LiveFrameQuality.usable);
  });

  test('quality advice remains concrete and non-approving', () {
    for (final value in LiveFrameQuality.values) {
      final advice = liveQualityAdvice(value);
      expect(advice.isNotEmpty, true);
      expect(advice.toLowerCase().contains('doğrulandı'), false);
    }
  });
}
