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

  test('blank line separating fabric sections requires review', () {
    const primary = 'DIS KUMAS\n80% PAMUK\n\nASTAR\n20% PES';
    final reading = compareReadings(
      primary,
      'DIS KUMAS\n80% PAMUK\nASTAR\n20% PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isTrue);
    expect(reading.acceptedText, primary);
  });

  test('leading and trailing empty lines are not section changes', () {
    final reading = compareReadings(
      '\n\n80% PAMUK\n',
      '80% PAMUK',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
  });

  test('CRLF and LF preserve the same internal section boundary', () {
    final reading = compareReadings(
      '80% PAMUK\r\n\r\nASTAR\r\n20% PES',
      '80% PAMUK\n\nASTAR\n20% PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
  });

  test('Unicode line and paragraph separators match physical line breaks', () {
    final reading = compareReadings(
      '80% PAMUK\u2028\u2028ASTAR\u202920% PES',
      '80% PAMUK\n\nASTAR\n20% PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isFalse);
  });

  test('Unicode paragraph boundary is not silently flattened', () {
    final reading = compareReadings(
      '80% PAMUK\u2029ASTAR 20% PES',
      '80% PAMUK ASTAR 20% PES',
    );
    expect(reading.percentageTokensDiffer, isFalse);
    expect(reading.percentageContextDiffers, isTrue);
  });

  test('Unicode line break never joins a number to its percent sign', () {
    final reading = compareReadings(
      '80\u2028% PAMUK',
      '80% PAMUK',
    );
    expect(reading.percentageTokensDiffer, isTrue);
  });
}
