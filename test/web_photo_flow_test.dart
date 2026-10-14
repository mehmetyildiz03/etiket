import 'dart:async';
import 'package:etiket/main.dart';
import 'package:etiket/scan/web_scan_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'web_scan_services_test.dart' show FakeBridge;
import 'photo_flow_test.dart' show imagePhoto, tapPending;
import 'widget_test.dart' show tapText, continueButton;

void main() {
  for (final width in [360.0, 390.0, 430.0, 1280.0]) {
    testWidgets(
      'web $width: upload, editable OCR and required approval with keyboard',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final bridge = FakeBridge()
          ..selection = BrowserPhoto(
            'blob:local',
            imagePhoto('fixture').previewBytes,
          );
        await tester.pumpWidget(
          EtiketApp(
            photoSource: WebPhotoSource(bridge),
            textRecognizer: WebTextRecognizer(bridge),
          ),
        );
        await tester.pumpAndSettle();
        await tapText(tester, 'Etiket tara');
        expect(find.text('Fotoğraf çek'), findsNothing);
        expect(find.textContaining('9 MB'), findsOneWidget);
        await tapText(tester, 'Fotoğraf yükle / galeriden seç');
        await tapText(tester, 'Fotoğraftaki metni oku');
        await tapText(tester, 'Metni incele ve düzelt');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(
          find.byKey(const ValueKey('label-text')),
          'Dış kumaş\n80% CO 20% PES\nLining\n100% VI',
        );
        await tapText(tester, 'Metni ayrıştır');
        await tapText(tester, 'Düzenleyicide incele');
        expect(continueButton(tester).onPressed, isNull);
        await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
        expect(continueButton(tester).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        expect(bridge.released, ['blob:local']);
      },
    );
  }
  testWidgets(
    'web model error/retry and cancel expose progress and keep fallback',
    (tester) async {
      final bridge = FakeBridge()
        ..cameraAvailable = true
        ..selection = BrowserPhoto(
          'blob:local',
          imagePhoto('fixture').previewBytes,
        );
      await tester.pumpWidget(
        EtiketApp(
          photoSource: WebPhotoSource(bridge),
          textRecognizer: WebTextRecognizer(bridge),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Etiket tara');
      await tapText(tester, 'Fotoğraf çek');
      bridge.error = 'modelLoad';
      await tapText(tester, 'Fotoğraftaki metni oku');
      expect(
        find.textContaining('İlk kullanım için internet gerekir'),
        findsOneWidget,
      );
      bridge.error = null;
      bridge.pending = Completer();
      await tapPending(tester, 'Tekrar oku');
      expect(find.text('Dil modeli indiriliyor…'), findsOneWidget);
      await tapPending(tester, 'İşlemi iptal et');
      bridge.pending!.complete('100% WO');
      await tester.pumpAndSettle();
      expect(find.text('Metni incele ve düzelt'), findsNothing);
      await tapText(tester, 'Metin yapıştır');
      expect(find.byKey(const ValueKey('label-text')), findsOneWidget);
    },
  );
}
