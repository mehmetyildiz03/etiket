import 'package:etiket/scan/ocr_observation.dart';
import 'package:etiket/ui/ocr_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OcrObservation _observation(OcrSecondReading second) => OcrObservation(
  rawText: '80% PAMUK',
  confidence: 70,
  decision: OcrDecision.candidate,
  secondReading: second,
);

Future<void> _showDiagnostics(
  WidgetTester tester,
  OcrObservation observation,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OcrDiagnostics(observation: observation),
      ),
    ),
  ));
  expect(find.byKey(const ValueKey('second-ocr-provenance')), findsNothing);
  expect(find.byKey(const ValueKey('second-ocr-diagnostic')), findsNothing);
  expect(find.byKey(const ValueKey('third-ocr-diagnostic')), findsNothing);
  await tester.tap(find.text("OCR'nin okuduğu ham metni göster"));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('verified sparse Tesseract source is labeled only after opt-in',
      (tester) async {
    final evidence = _observation(OcrSecondReading(
      rawText: '20% PAMUK',
      confidence: 90,
      engine: OcrReadingEngine.tesseractJs,
      variant: OcrReadingVariant.sparseTextPsm11,
    ));
    await _showDiagnostics(tester, evidence);
    expect(
      find.text('İkinci okuma kaynağı: Tesseract.js — seyrek metin (PSM 11).'),
      findsOneWidget,
    );
    expect(find.textContaining('Aynı fotoğraf farklı metin'), findsOneWidget);
    expect(evidence.acceptedText, '80% PAMUK');
    await tester.tap(find.text('Ham OCR metnini gizle'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('second-ocr-provenance')), findsNothing);
  });

  testWidgets('rejected scan reveals PSM3 evidence only by explicit request',
      (tester) async {
    final evidence = OcrObservation(
      rawText: 'COMPOSITION 60 POLYESTER 40 COTTON',
      confidence: 33,
      decision: OcrDecision.lowConfidence,
      secondReading: OcrSecondReading(
        rawText: '60% Polyester\\n40% Cotton',
        confidence: 90,
        engine: OcrReadingEngine.tesseractJs,
        variant: OcrReadingVariant.automaticPagePsm3,
      ),
    );
    await _showDiagnostics(tester, evidence);
    expect(
      find.text('İkinci okuma kaynağı: Tesseract.js — otomatik sayfa bölümleme (PSM 3).'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('second-ocr-diagnostic')), findsOneWidget);
    expect(evidence.acceptedText, isNull,
        reason: 'PSM3 output must never be accepted automatically');
    expect(find.textContaining('İlk okuma reddedilmişse'), findsOneWidget);
    await tester.tap(find.text('Ham OCR metnini gizle'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('second-ocr-diagnostic')), findsNothing);
  });

  testWidgets('rejected PSM6 exposes independent PSM3 and PSM11 only on opt-in',
      (tester) async {
    final evidence = OcrObservation(
      rawText: 'SYNTHETIC UNREADABLE FRAGMENTS',
      confidence: 35,
      decision: OcrDecision.lowConfidence,
      secondReading: OcrSecondReading(
        rawText: 'Fiber Sample',
        confidence: 67,
        engine: OcrReadingEngine.tesseractJs,
        variant: OcrReadingVariant.automaticPagePsm3,
      ),
      thirdReading: OcrSecondReading(
        rawText: '80% Polyester',
        confidence: 75,
        engine: OcrReadingEngine.tesseractJs,
        variant: OcrReadingVariant.sparseTextPsm11,
      ),
    );
    await _showDiagnostics(tester, evidence);
    expect(find.byKey(const ValueKey('second-ocr-diagnostic')), findsOneWidget);
    expect(find.byKey(const ValueKey('third-ocr-diagnostic')), findsOneWidget);
    expect(find.textContaining('Üçüncü okuma kaynağı: Tesseract.js'), findsOneWidget);
    expect(evidence.acceptedText, isNull);
    await tester.tap(find.text('Ham OCR metnini gizle'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('third-ocr-diagnostic')), findsNothing);
  });

  testWidgets('unspecified secondary source is never presented as verified',
      (tester) async {
    final evidence = _observation(OcrSecondReading(
      rawText: '20% PAMUK',
      confidence: null,
    ));
    await _showDiagnostics(tester, evidence);
    expect(
      find.text('İkinci okuma kaynağı: motor veya yöntem doğrulanmadı.'),
      findsOneWidget,
    );
    expect(find.textContaining('Alternatif okumanın üretildiği motor'),
        findsOneWidget);
    expect(find.textContaining('Aynı fotoğraf farklı metin'), findsNothing);
    expect(find.textContaining('doğru olma olasılığı değildir'),
        findsOneWidget);
    expect(evidence.acceptedText, '80% PAMUK');
  });
}
