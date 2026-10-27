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
  test('nonbreaking inline spaces around explicit % do not invent a conflict', () {
    final reading = compare(
      '80\u00A0% PAMUK\n20\u202F% PES',
      '%80 PAMUK\n%20 PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
    // Diagnostic comparison must never normalize the actual editable OCR text.
    expect(reading.acceptedText, '80\u00A0% PAMUK\n20\u202F% PES');
  });

  test('nonbreaking spaces do not conceal changed values or fiber context', () {
    expect(
      compare('8\u00A0% PAMUK', '80% PAMUK').percentageTokensDiffer,
      isTrue,
    );
    expect(
      compare('80\u00A0% PAMUK', '80% PES').percentageContextDiffers,
      isTrue,
    );
    expect(
      compare('80\u202F% PAMUK', '80% PAMUK').percentageTokensDiffer,
      isFalse,
    );
  });

  test('malformed and line-separated numbers remain untrusted', () {
    expect(
      compare('1234\u00A0% PAMUK', '234% PAMUK').percentageTokensDiffer,
      isTrue,
    );
    expect(
      compare('80\n% PAMUK', '80% PAMUK').percentageTokensDiffer,
      isTrue,
    );
    expect(
      compare('80\u00A0% PAMUK', '80\u00A0% PAMUK').acceptedText,
      '80\u00A0% PAMUK',
    );
  });
}
