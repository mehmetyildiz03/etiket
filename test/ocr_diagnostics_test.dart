import 'dart:async';
import 'package:etiket/main.dart';
import 'package:etiket/scan/ocr_observation.dart';
import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/photo_edit.dart';
import 'package:etiket/scan/web_scan_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'photo_scan_test.dart' show FakeRecognizer;
import 'photo_edit_test.dart' show EditingPhotos, editablePhoto;
import 'web_scan_services_test.dart' show FakeBridge;
import 'widget_test.dart' show tapText, continueButton;

const showRaw = "OCR'nin okuduğu ham metni göster";
const rawWarning = 'Ham OCR çıktısı — doğrulanmış kumaş bileşimi değildir';
OcrObservation observation(OcrDecision decision) => OcrObservation(
  rawText: decision == OcrDecision.noText ? '' : '  PLEASE CLOSE THE DOOR\n',
  confidence: decision == OcrDecision.lowConfidence ? 12 : 95,
  decision: decision,
);
OcrObservation candidate(String text) => OcrObservation(
  rawText: text,
  confidence: 95,
  decision: OcrDecision.candidate,
);

class DiagnosticBridge extends FakeBridge
    implements BrowserDiagnosticScanBridge {
  OcrObservation result = observation(OcrDecision.noComposition);
  final pendingResults = <Completer<OcrObservation>>[];
  int legacyCalls = 0;
  @override
  Future<String> recognize(String path, void Function(String) progress) async {
    legacyCalls++;
    return super.recognize(path, progress);
  }

  @override
  Future<OcrObservation> recognizeObservation(
    String path,
    void Function(String) progress,
  ) async {
    progress('Etiket cihazında okunuyor…');
    if (error != null) throw BrowserScanException(error!);
    return pendingResults.isEmpty ? result : pendingResults.removeAt(0).future;
  }
}

void main() {
  test(
    'invalid confidence/oversized/candidate evidence cannot enter the model',
    () {
      for (final confidence in [double.nan, double.infinity, -1.0, 101.0]) {
        expect(
          () => OcrObservation(
            rawText: 'text',
            confidence: confidence,
            decision: OcrDecision.noComposition,
          ),
          throwsArgumentError,
        );
      }
      expect(() => candidate(' '), throwsArgumentError);
      expect(() => candidate('x' * 20001), throwsArgumentError);
      expect(
        () => OcrObservation(
          rawText: '100% CO',
          confidence: null,
          decision: OcrDecision.candidate,
        ),
        throwsArgumentError,
      );
      expect(
        () => OcrObservation(
          rawText: '100% CO',
          confidence: 44,
          decision: OcrDecision.candidate,
        ),
        throwsArgumentError,
      );
    },
  );

  late DiagnosticBridge bridge;
  late EditingPhotos photos;
  late PhotoScanController scan;
  setUp(() {
    bridge = DiagnosticBridge();
    photos = EditingPhotos()..next = editablePhoto('first');
    scan = PhotoScanController(photos, WebTextRecognizer(bridge));
  });
  tearDown(() => scan.dispose());

  for (final decision in [
    OcrDecision.noText,
    OcrDecision.noComposition,
    OcrDecision.lowConfidence,
  ]) {
    test('$decision preserves engine evidence without parser input', () async {
      bridge.result = observation(decision);
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      expect(scan.stage, ScanStage.failed);
      expect(scan.text, isEmpty);
      expect(scan.observation, same(bridge.result));
      expect(scan.observation!.acceptedText, isNull);
      expect(scan.message, bridge.result.explanation);
      expect(bridge.legacyCalls, 0);
    });
  }
  test(
    'distinct explanations; only a candidate enters editable unverified text',
    () async {
      expect(
        OcrDecision.values.map((d) => observation(d).explanation).toSet(),
        hasLength(4),
      );
      bridge.result = candidate('80% CO 20% PES\n');
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      expect(scan.stage, ScanStage.ready);
      expect(scan.text, bridge.result.rawText);
      expect(scan.observation!.decision, OcrDecision.candidate);
    },
  );
  test(
    'native/legacy failures retain their own message without web diagnostics',
    () async {
      final native = PhotoScanController(photos, FakeRecognizer()..result = '');
      addTearDown(native.dispose);
      await native.pick(PhotoSource.camera);
      await native.recognize();
      expect(
        native.message,
        const ScanFailure(ScanFailureKind.emptyText).message,
      );
      expect(native.observation, isNull);
    },
  );
  test(
    'a retry clears evidence before reading; model failure is not a label rejection',
    () async {
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      final pending = Completer<OcrObservation>();
      bridge.pendingResults.add(pending);
      final reading = scan.recognize();
      expect(scan.observation, isNull);
      pending.completeError(const BrowserScanException('modelLoad'));
      await reading;
      expect(scan.observation, isNull);
      expect(scan.message, contains('motoru veya dil modeli yüklenemedi'));
      expect(scan.text, isEmpty);
    },
  );
  for (final action in ['edit', 'cancel', 'abandon', 'dispose', 'crop']) {
    test(
      '$action clears evidence and blocks late diagnostic results',
      () async {
        await scan.pick(PhotoSource.gallery);
        await scan.recognize();
        expect(scan.observation, isNotNull);
        final pending = Completer<OcrObservation>();
        bridge.pendingResults.add(pending);
        final reading = scan.recognize();
        switch (action) {
          case 'edit':
            scan.editText('80% CO 20% PES');
          case 'cancel':
            scan.cancel();
          case 'abandon':
            scan.abandon();
          case 'dispose':
            scan.dispose();
          case 'crop':
            expect(scan.beginPhotoEdit(), isTrue);
        }
        pending.complete(candidate('100% WO'));
        await reading;
        expect(scan.observation, isNull);
        expect(scan.text, action == 'edit' ? '80% CO 20% PES' : '');
      },
    );
  }
  test(
    'new photo with reversed completions retains only the latest evidence',
    () async {
      await scan.pick(PhotoSource.gallery);
      final a = Completer<OcrObservation>(), b = Completer<OcrObservation>();
      bridge.pendingResults.addAll([a, b]);
      final older = scan.recognize();
      photos.next = editablePhoto('second');
      await scan.pick(PhotoSource.gallery);
      final newer = scan.recognize();
      b.complete(candidate('100% VI'));
      await newer;
      a.complete(observation(OcrDecision.noComposition));
      await older;
      expect(scan.text, '100% VI');
      expect(scan.observation!.rawText, '100% VI');
      expect(scan.photo!.path, 'second');
    },
  );
  test(
    'cancelled picker and crop/reset invalidate previous photo evidence',
    () async {
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      photos.next = null;
      await scan.pick(PhotoSource.gallery);
      expect(scan.observation, isNull);
      await scan.recognize();
      expect(scan.beginPhotoEdit(), isTrue);
      expect(scan.observation, isNull);
      expect(
        await scan.applyPhotoEdit(const PhotoEdit(quarterTurns: 1)),
        isTrue,
      );
      await scan.recognize();
      expect(scan.observation, isNotNull);
      expect(scan.beginPhotoEdit(), isTrue);
      expect(await scan.applyPhotoEdit(const PhotoEdit()), isTrue);
      expect(scan.observation, isNull);
    },
  );

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      '$width: opt-in raw evidence, back/retry reset, manual entry and keyboard approval',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final oldFatal = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(
          () => WidgetController.hitTestWarningShouldBeFatal = oldFatal,
        );
        await tester.pumpWidget(
          EtiketApp(
            photoSource: photos,
            textRecognizer: WebTextRecognizer(bridge),
          ),
        );
        await tester.pumpAndSettle();
        await tapText(tester, 'Etiket tara');
        await tapText(tester, 'Galeriden seç');
        await tapText(tester, 'Fotoğraftaki metni oku');
        expect(find.byKey(const ValueKey('raw-ocr-diagnostic')), findsNothing);
        expect(find.text('Metni incele ve düzelt'), findsNothing);
        await tapText(tester, showRaw);
        expect(find.text(rawWarning), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('raw-ocr-diagnostic')),
              )
              .data,
          bridge.result.rawText,
        );
        expect(find.text('Motor güven puanı: 95.0 / 100'), findsOneWidget);
        await tapText(tester, 'Tekrar oku');
        expect(find.byKey(const ValueKey('raw-ocr-diagnostic')), findsNothing);
        await tapText(tester, showRaw);
        await tester.tap(find.byTooltip('Geri'));
        await tester.pumpAndSettle();
        await tapText(tester, 'Etiket tara');
        expect(find.text(showRaw), findsNothing);
        await tapText(tester, 'Galeriden seç');
        await tapText(tester, 'Fotoğraftaki metni oku');
        await tapText(tester, showRaw);
        await tapText(tester, 'Metin yapıştır');
        final field = find.byKey(const ValueKey('label-text'));
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(field, '80% CO 20% PES');
        await tapText(tester, 'Metni ayrıştır');
        await tapText(tester, 'Düzenleyicide incele');
        expect(continueButton(tester).onPressed, isNull);
        await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
        expect(continueButton(tester).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'candidate still requires manual review, percentage validation and explicit approval',
    (tester) async {
      bridge.result = candidate('80% CO 20% PES');
      await tester.pumpWidget(
        EtiketApp(
          photoSource: photos,
          textRecognizer: WebTextRecognizer(bridge),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Etiket tara');
      await tapText(tester, 'Galeriden seç');
      await tapText(tester, 'Fotoğraftaki metni oku');
      await tapText(tester, showRaw);
      expect(find.text(rawWarning), findsOneWidget);
      await tapText(tester, 'Metni incele ve düzelt');
      final field = find.byKey(const ValueKey('label-text'));
      expect(
        tester.widget<TextField>(field).controller!.text,
        bridge.result.rawText,
      );
      await tester.enterText(field, '60% CO 20% PES');
      await tapText(tester, 'Metni ayrıştır');
      await tapText(tester, 'Düzenleyicide incele');
      await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
      expect(continueButton(tester).onPressed, isNull);
    },
  );
  for (final decision in [OcrDecision.noText, OcrDecision.lowConfidence]) {
    testWidgets('$decision explains engine evidence without a review action', (
      tester,
    ) async {
      bridge.result = OcrObservation(
        rawText: decision == OcrDecision.noText
            ? ''
            : 'possibly invented letters',
        confidence: decision == OcrDecision.noText ? 0 : null,
        decision: decision,
      );
      await tester.pumpWidget(
        EtiketApp(
          photoSource: photos,
          textRecognizer: WebTextRecognizer(bridge),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Etiket tara');
      await tapText(tester, 'Galeriden seç');
      await tapText(tester, 'Fotoğraftaki metni oku');
      expect(find.text(bridge.result.explanation), findsOneWidget);
      expect(find.text('Metni incele ve düzelt'), findsNothing);
      expect(find.byKey(const ValueKey('raw-ocr-diagnostic')), findsNothing);
      await tapText(tester, showRaw);
      expect(find.text(rawWarning), findsOneWidget);
      if (decision == OcrDecision.noText) {
        expect(find.text('Motor boş metin döndürdü.'), findsOneWidget);
        expect(find.text('Motor güven puanı: 0.0 / 100'), findsOneWidget);
      } else {
        expect(find.text('Motor güven puanı: mevcut değil.'), findsOneWidget);
        expect(find.textContaining('hayali harfler'), findsOneWidget);
      }
      await tapText(tester, 'Ham OCR metnini gizle');
      expect(find.text(rawWarning), findsNothing);
    });
  }

  test('a weak accepted OCR candidate is explicitly marked for correction', () {
    final weak = OcrObservation(
      rawText: 'OF 0% Polyester\\n% 40% Cotton',
      confidence: 48,
      decision: OcrDecision.candidate,
    );
    expect(weak.acceptedText, weak.rawText);
    expect(weak.candidateWarning, contains('48.0'));
    expect(weak.candidateWarning, contains('yüzde'));
    expect(weak.candidateWarning, contains('doğruluk olasılığı'));
    expect(candidate('60% Polyester\\n40% Cotton').candidateWarning, isNull);
  });

  testWidgets('48-point accepted candidate visibly warns before manual review', (
    tester,
  ) async {
    bridge.result = OcrObservation(
      rawText: 'OF 0% Polyester\\n% 40% Cotton',
      confidence: 48,
      decision: OcrDecision.candidate,
    );
    await tester.pumpWidget(
      EtiketApp(photoSource: photos, textRecognizer: WebTextRecognizer(bridge)),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Etiket tara');
    await tapText(tester, 'Galeriden seç');
    await tapText(tester, 'Fotoğraftaki metni oku');
    expect(find.textContaining('Düşük OCR güveni'), findsOneWidget);
    expect(find.textContaining('48.0'), findsOneWidget);
    expect(find.text('Metni incele ve düzelt'), findsOneWidget);
    await tapText(tester, 'Metni incele ve düzelt');
    final field = find.byKey(const ValueKey('label-text'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      bridge.result.rawText,
    );
  });
}
