import 'package:etiket/scan/ocr_observation.dart';
import 'package:flutter_test/flutter_test.dart';

OcrObservation compare(String primary, String alternative) => OcrObservation(
      rawText: primary,
      confidence: 70,
      decision: OcrDecision.candidate,
      secondReading: OcrSecondReading(
        rawText: alternative,
        confidence: 95,
      ),
    );

void main() {
  test('inline Unicode spaces in fiber context are diagnostic equivalents', () {
    final reading = compare(
      '80% PAMUK\u00A0PES\n20% VISKON\u202FASTAR',
      '80% PAMUK PES\n20% VISKON ASTAR',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
    expect(reading.acceptedText, '80% PAMUK\u00A0PES\n20% VISKON\u202FASTAR');
  });

  test('inline space normalization never hides changed fibers', () {
    final reading = compare(
      '80% PAMUK\u00A0PES',
      '80% PAMUK VISKON',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isTrue);
  });

  test('line grouping and section changes remain review signals', () {
    expect(
      compare('80% PAMUK\n20% PES', '80% PAMUK 20% PES')
          .percentageContextDiffers,
      isTrue,
    );
    expect(
      compare('DIŞ KUMAŞ\n80% PAMUK', 'ASTAR\n80% PAMUK')
          .percentageContextDiffers,
      isTrue,
    );
  });
}
