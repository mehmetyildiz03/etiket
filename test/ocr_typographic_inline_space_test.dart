import 'package:etiket/scan/ocr_observation.dart';
import 'package:flutter_test/flutter_test.dart';

OcrObservation compareReadings(String primary, String secondary) =>
    OcrObservation(
      rawText: primary,
      confidence: 70,
      decision: OcrDecision.candidate,
      secondReading: OcrSecondReading(
        rawText: secondary,
        confidence: 95,
      ),
    );

void main() {
  test('thin and figure spaces next to percentages are equivalent', () {
    const primary = '80\u2009% PAMUK\u2007PES\n%\u200780 ASTAR';
    final reading = compareReadings(
      primary,
      '80% PAMUK PES\n%80 ASTAR',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
    expect(reading.acceptedText, primary);
  });

  test('typographic spaces do not hide changed percentage values', () {
    final reading = compareReadings(
      '80\u2009% PAMUK',
      '81% PAMUK',
    );
    expect(reading.percentageTokensDiffer, isTrue);
  });

  test('typographic spaces do not hide changed fiber names', () {
    final reading = compareReadings(
      '80% PAMUK\u2007PES',
      '80% PAMUK VISKON',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isTrue);
  });

  test('line breaks never become inline percent separators', () {
    final reading = compareReadings(
      '80\n% PAMUK',
      '80% PAMUK',
    );
    expect(reading.percentageTokensDiffer, isTrue);
  });

  test('line grouping still produces a review signal', () {
    final reading = compareReadings(
      '80% PAMUK\n20% PES',
      '80% PAMUK 20% PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isTrue);
  });

  test('oversized percentage is not partially extracted', () {
    final reading = compareReadings(
      '1234\u2009% PAMUK',
      '34% PAMUK',
    );
    expect(reading.percentageTokensDiffer, isTrue);
  });
}
