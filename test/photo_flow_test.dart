import 'dart:async';
import 'dart:convert';

import 'package:etiket/main.dart';
import 'package:etiket/scan/photo_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'photo_scan_test.dart' show FakePhotos, FakeRecognizer;
import 'widget_test.dart' show tapText, field, continueButton;

ScanPhoto imagePhoto(String id) => ScanPhoto(
  path: id,
  previewBytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
  ),
);

Future<void> launchScan(
  WidgetTester tester,
  FakePhotos photos,
  FakeRecognizer ocr, {
  Size size = const Size(390, 844),
  bool openCamera = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final previousHitTestCheck = WidgetController.hitTestWarningShouldBeFatal;
  WidgetController.hitTestWarningShouldBeFatal = true;
  addTearDown(
    () => WidgetController.hitTestWarningShouldBeFatal = previousHitTestCheck,
  );
  await tester.pumpWidget(EtiketApp(photoSource: photos, textRecognizer: ocr));
  await tester.pumpAndSettle();
  if (openCamera) await tapText(tester, 'Etiket tara');
}

Future<void> acquire(
  WidgetTester tester, {
  String source = 'Fotoğraf çek',
}) async {
  await tapText(tester, source);
  expect(find.byKey(const ValueKey('photo-preview')), findsOneWidget);
}

Future<void> readAndEdit(WidgetTester tester) async {
  await acquire(tester);
  await tapText(tester, 'Fotoğraftaki metni oku');
  await tapText(tester, 'Metni incele ve düzelt');
}

// A pending OCR/picker animates its progress indicator indefinitely. Interact
// with a bounded pump rather than waiting for that animation to settle.
Future<void> tapPending(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  late FakePhotos photos;
  late FakeRecognizer ocr;
  setUp(() {
    photos = FakePhotos()..next = imagePhoto('selected');
    ocr = FakeRecognizer();
  });

  testWidgets(
    'OCR text stays editable and unverified through multiple sections',
    (tester) async {
      await launchScan(tester, photos, ocr);
      await acquire(tester, source: 'Galeriden seç');
      expect(ocr.calls, isEmpty);
      await tapText(tester, 'Fotoğraftaki metni oku');
      expect(find.text('Okunan metin — henüz doğrulanmadı'), findsOneWidget);
      await tapText(tester, 'Metni incele ve düzelt');
      expect(find.text('Fotoğraftan okunan metin'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('label-text')))
            .controller!
            .text,
        ocr.result,
      );
      expect(photos.released, contains(photos.next));
      await tapText(tester, 'Metni ayrıştır');
      await tapText(tester, 'Düzenleyicide incele');
      expect(continueButton(tester).onPressed, isNull);
      await tester.enterText(field('Yüzde').first, '80');
      await tester.enterText(field('Yüzde').at(1), '20');
      await tester.pump();
      expect(continueButton(tester).onPressed, isNull);
      await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
      await tapText(tester, 'Devam et');
      await tapText(tester, 'Analizi göster');
      expect(find.text('Pamuk %80 · Polyester %20'), findsOneWidget);
      expect(find.text('Viskon %100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final source in ['Fotoğraf çek', 'Galeriden seç']) {
    testWidgets(
      '$source cancellation and permission errors have working fallbacks',
      (tester) async {
        photos.next = null;
        await launchScan(tester, photos, ocr);
        await tapText(tester, source);
        expect(find.text('Fotoğraf seçimi iptal edildi.'), findsOneWidget);
        photos.error = const ScanFailure(
          ScanFailureKind.permission,
          permanent: true,
        );
        await tapText(tester, source);
        expect(find.textContaining('Telefon ayarlarından'), findsOneWidget);
        expect(ocr.calls, isEmpty);
        await tapText(tester, 'Metin yapıştır');
        expect(find.byKey(const ValueKey('label-text')), findsOneWidget);
      },
    );
  }
  testWidgets('OCR failure and empty text permit retry or manual entry', (
    tester,
  ) async {
    await launchScan(tester, photos, ocr);
    await acquire(tester);
    ocr.error = StateError('failure');
    await tapText(tester, 'Fotoğraftaki metni oku');
    expect(find.textContaining('Etiket okunamadı'), findsOneWidget);
    ocr.error = null;
    ocr.result = ' \n ';
    await tapText(tester, 'Tekrar oku');
    expect(find.textContaining('okunabilir yazı bulunamadı'), findsOneWidget);
    ocr.result = '100% CO';
    await tapText(tester, 'Tekrar oku');
    expect(find.text('Okunan metin — henüz doğrulanmadı'), findsOneWidget);
    await tapText(tester, 'Elle giriş');
    expect(find.text('Kumaş içeriğini doğrula'), findsOneWidget);
  });
  testWidgets('ambiguous OCR is not silently repaired or confirmed', (
    tester,
  ) async {
    ocr.result = '7O% CO\nmystery fiber';
    await launchScan(tester, photos, ocr);
    await readAndEdit(tester);
    await tapText(tester, 'Metni ayrıştır');
    expect(find.textContaining('Yüzde okunamadı'), findsWidgets);
    await tapText(tester, 'Düzenleyicide incele');
    expect(continueButton(tester).onPressed, isNull);
    expect(find.textContaining('Elyafı elle seçin'), findsWidgets);
  });
  testWidgets('late OCR cannot overwrite pasted text after leaving scan', (
    tester,
  ) async {
    await launchScan(tester, photos, ocr);
    await acquire(tester);
    final completion = Completer<String>();
    ocr.pending.add(completion);
    await tapPending(tester, 'Fotoğraftaki metni oku');
    expect(ocr.calls, hasLength(1));
    await tapPending(tester, 'Metin yapıştır');
    await tester.enterText(
      find.byKey(const ValueKey('label-text')),
      '80% CO 20% PES',
    );
    completion.complete('100% WO');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('label-text')))
          .controller!
          .text,
      '80% CO 20% PES',
    );
    expect(find.text('Fotoğraftan okunan metin'), findsNothing);
    expect(photos.released, contains(photos.next));
  });
  testWidgets(
    'a new scan cannot replace existing raw text without permission',
    (tester) async {
      await launchScan(tester, photos, ocr);
      await tapText(tester, 'Metin yapıştır');
      await tester.enterText(
        find.byKey(const ValueKey('label-text')),
        '100% CO',
      );
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await readAndEdit(tester);
      expect(find.text('Önceki metin değiştirilsin mi?'), findsOneWidget);
      await tapText(tester, 'Metnimi koru');
      await tapText(tester, 'Metin yapıştır');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('label-text')))
            .controller!
            .text,
        '100% CO',
      );
    },
  );
  testWidgets(
    'accepted manual composition requires explicit OCR replacement too',
    (tester) async {
      await launchScan(tester, photos, ocr);
      await tapText(tester, 'Elle giriş');
      await tester.enterText(field('Yüzde').first, '80');
      await tester.enterText(field('Yüzde').last, '20');
      await tester.pump();
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await readAndEdit(tester);
      await tapText(tester, 'Metni ayrıştır');
      await tapText(tester, 'Düzenleyicide incele');
      expect(
        find.text('Mevcut düzenlemeler değiştirilsin mi?'),
        findsOneWidget,
      );
      await tapText(tester, 'Düzenlemeleri koru');
      await tapText(tester, 'Elle girişe dön');
      final input = tester.widget<TextField>(
        find.descendant(
          of: field('Yüzde').first,
          matching: find.byType(TextField),
        ),
      );
      expect(input.controller!.text, '80');
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets(
      '${size.width}: keyboard and system back preserve corrected OCR',
      (tester) async {
        await launchScan(tester, photos, ocr, size: size);
        await readAndEdit(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(
          find.byKey(const ValueKey('label-text')),
          '100% CO',
        );
        await tapText(tester, 'Metni ayrıştır');
        await tapText(tester, 'Düzenleyicide incele');
        expect(continueButton(tester).onPressed, isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('label-text')))
              .controller!
              .text,
          '100% CO',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'backgrounding OCR invalidates its result but not external picker selection',
    (tester) async {
      await launchScan(tester, photos, ocr);
      await acquire(tester);
      final completion = Completer<String>();
      ocr.pending.add(completion);
      await tapPending(tester, 'Fotoğraftaki metni oku');
      expect(ocr.calls, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      completion.complete('100% WO');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tarama duraklatıldı'), findsOneWidget);
      expect(find.text('Metni incele ve düzelt'), findsNothing);
      photos.pending = Completer();
      await tapPending(tester, 'Galeriden seç');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      photos.pending!.complete(imagePhoto('returned'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-preview')), findsOneWidget);
      expect(photos.sources, [PhotoSource.camera, PhotoSource.gallery]);
    },
  );
  testWidgets(
    'system back during OCR cleans after completion and never navigates back',
    (tester) async {
      await launchScan(tester, photos, ocr);
      await acquire(tester);
      final completion = Completer<String>();
      ocr.pending.add(completion);
      await tapPending(tester, 'Fotoğraftaki metni oku');
      expect(ocr.calls, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pump();
      completion.complete('100% WO');
      await tester.pumpAndSettle();
      expect(find.text('Etiket tara'), findsOneWidget);
      expect(photos.released, contains(photos.next));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported web-like platform keeps manual/pasted/demo input', (
    tester,
  ) async {
    photos.supported = false;
    await launchScan(tester, photos, ocr);
    expect(find.textContaining('OCR desteklenmiyor'), findsOneWidget);
    expect(find.text('Fotoğraf çek'), findsNothing);
    expect(find.text('Galeriden seç'), findsNothing);
    expect(find.text('DEMO — fotoğraf veya OCR kullanılmaz'), findsOneWidget);
    await tapText(tester, 'Metin yapıştır');
    await tester.enterText(find.byKey(const ValueKey('label-text')), '100% CO');
    await tapText(tester, 'Metni ayrıştır');
    await tapText(tester, 'Düzenleyicide incele');
    expect(continueButton(tester).onPressed, isNull);
    expect(photos.sources, isEmpty);
    expect(ocr.calls, isEmpty);
  });
  testWidgets(
    'rapid duplicate selection is ignored and cancel ignores the late selection',
    (tester) async {
      await launchScan(tester, photos, ocr);
      photos.pending = Completer();
      await tapPending(tester, 'Fotoğraf çek');
      await tapPending(tester, 'Fotoğraf çek');
      expect(photos.sources, [PhotoSource.camera]);
      await tapPending(tester, 'İşlemi iptal et');
      final late = imagePhoto('late');
      photos.pending!.complete(late);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-preview')), findsNothing);
      expect(photos.released, contains(late));
      expect(ocr.calls, isEmpty);
    },
  );
  testWidgets(
    'two reversed OCR results keep the newest photo and text in the UI',
    (tester) async {
      final first = photos.next!;
      final a = Completer<String>(), b = Completer<String>();
      ocr.pending.addAll([a, b]);
      await launchScan(tester, photos, ocr);
      await acquire(tester);
      await tapPending(tester, 'Fotoğraftaki metni oku');
      photos.next = imagePhoto('new');
      await tapPending(tester, 'Galeriden seç');
      await tester.pumpAndSettle();
      await tapPending(tester, 'Fotoğraftaki metni oku');
      expect(ocr.calls, hasLength(2));
      b.complete('100% VI');
      await tester.pumpAndSettle();
      a.complete('100% WO');
      await tester.pumpAndSettle();
      expect(find.text('100% VI'), findsOneWidget);
      expect(find.text('100% WO'), findsNothing);
      expect(photos.released, contains(first));
    },
  );
  testWidgets(
    'lost Android photo reopens preview without automatically recognizing it',
    (tester) async {
      photos.recovered = imagePhoto('recovered');
      await launchScan(tester, photos, ocr, openCamera: false);
      expect(find.byKey(const ValueKey('photo-preview')), findsOneWidget);
      expect(find.text('Fotoğraftaki metni oku'), findsOneWidget);
      expect(ocr.calls, isEmpty);
    },
  );
  testWidgets(
    'late recovered Android photo cannot displace a manual correction',
    (tester) async {
      photos.pendingRecovery = Completer();
      await launchScan(tester, photos, ocr, openCamera: false);
      await tapText(tester, 'Elle kumaş bilgisi gir');
      await tester.enterText(field('Yüzde').first, '80');
      await tester.enterText(field('Yüzde').last, '20');
      final recovered = imagePhoto('late-recovery');
      photos.pendingRecovery!.complete(recovered);
      await tester.pumpAndSettle();
      expect(find.text('Kumaş içeriğini doğrula'), findsOneWidget);
      final input = tester.widget<TextField>(
        find.descendant(
          of: field('Yüzde').first,
          matching: find.byType(TextField),
        ),
      );
      expect(input.controller!.text, '80');
      expect(photos.released, contains(recovered));
    },
  );
}
