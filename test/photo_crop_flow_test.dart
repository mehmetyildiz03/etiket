import 'dart:async';
import 'package:etiket/main.dart';
import 'package:etiket/ui/photo_crop_editor.dart';
import 'package:etiket/scan/photo_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'photo_edit_test.dart' show EditingPhotos, editablePhoto;
import 'photo_scan_test.dart' show FakeRecognizer;
import 'widget_test.dart' show tapText, continueButton, field;

void main() {
  setUp(() {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
  });
  testWidgets('leaving a scan evicts the private decoded preview cache', (
    tester,
  ) async {
    final photos = EditingPhotos()..next = editablePhoto('original');
    await tester.pumpWidget(
      EtiketApp(photoSource: photos, textRecognizer: FakeRecognizer()),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Etiket tara');
    await tapText(tester, 'Galeriden seç');
    final provider = tester.widget<Image>(find.byType(Image).first).image;
    final cacheKey = await provider.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(cacheKey), true);
    await tapText(tester, 'Metin yapıştır');
    expect(PaintingBinding.instance.imageCache.containsKey(cacheKey), false);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'gradual diagonal corner drag wins over the vertical page scroll',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final photos = EditingPhotos()..next = editablePhoto('original');
      await tester.pumpWidget(
        EtiketApp(photoSource: photos, textRecognizer: FakeRecognizer()),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Etiket tara',
        'Galeriden seç',
        'Fotoğrafı düzenle',
      ]) {
        await tapText(tester, label);
      }
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('crop-bottom-right'))),
      );
      for (var step = 0; step < 8; step++) {
        await drag.moveBy(const Offset(-7, -5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pumpAndSettle();
      for (final key in ['crop-width', 'crop-height']) {
        final value = tester
            .widget<TextField>(find.byKey(ValueKey(key)))
            .controller!
            .text;
        expect(double.parse(value), lessThan(100));
      }
      expect(tester.takeException(), isNull);
    },
  );
  for (final change in ['crop', 'second photo']) {
    testWidgets(
      '$change revokes prior approval but preserves corrected draft',
      (tester) async {
        final photos = EditingPhotos()..next = editablePhoto('first');
        final ocr = FakeRecognizer()..result = '80% CO 20% PES';
        await tester.pumpWidget(
          EtiketApp(photoSource: photos, textRecognizer: ocr),
        );
        await tester.pumpAndSettle();
        for (final label in [
          'Etiket tara',
          'Galeriden seç',
          'Fotoğraftaki metni oku',
          'Metni incele ve düzelt',
          'Metni ayrıştır',
          'Düzenleyicide incele',
        ]) {
          await tapText(tester, label);
        }
        await tester.enterText(field('Yüzde').first, '75');
        await tester.enterText(field('Yüzde').at(1), '25');
        await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
        expect(continueButton(tester).onPressed, isNotNull);
        await tester.tap(find.byTooltip('Geri'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Geri'));
        await tester.pumpAndSettle();
        if (change == 'crop') {
          await tapText(tester, 'Fotoğrafı düzenle');
          await tapText(tester, '90° sağa');
          await tapText(tester, 'Kırpmayı uygula');
        } else {
          photos.next = editablePhoto('second');
          await tapText(tester, 'Başka fotoğraf seç');
        }
        await tapText(tester, 'Elle giriş');
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: field('Yüzde').first,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          '75',
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: field('Yüzde').at(1),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          '25',
        );
        expect(continueButton(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'multiple touches do not change selection; background cancels a pending crop',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final photos = EditingPhotos()..next = editablePhoto('original');
      await tester.pumpWidget(
        EtiketApp(photoSource: photos, textRecognizer: FakeRecognizer()),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Etiket tara',
        'Galeriden seç',
        'Fotoğrafı düzenle',
      ]) {
        await tapText(tester, label);
      }
      final handle = find.byKey(const ValueKey('crop-bottom-right'));
      final before = tester
          .widget<TextField>(find.byKey(const ValueKey('crop-width')))
          .controller!
          .text;
      final first = await tester.startGesture(
        tester.getCenter(handle),
        pointer: 1,
      );
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('crop-canvas'))),
        pointer: 2,
      );
      await first.moveBy(const Offset(-50, -20));
      await second.moveBy(const Offset(20, 10));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('crop-width')))
            .controller!
            .text,
        before,
      );
      await first.up();
      await second.up();
      final complete = Completer<ScanPhoto>();
      photos.pendingEdits.add(complete);
      final apply = find.text('Kırpmayı uygula');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(milliseconds: 500));
      complete.complete(editablePhoto('late'));
      await tester.pump(const Duration(milliseconds: 500));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCropEditor), findsNothing);
      expect(photos.released.map((p) => p.path), contains('late'));
      expect(find.text('Fotoğrafı düzenle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets(
      '$size crop corners, rotate, reset, keyboard, back and explicit approval',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final photos = EditingPhotos()..next = editablePhoto('original');
        final ocr = FakeRecognizer();
        await tester.pumpWidget(
          EtiketApp(photoSource: photos, textRecognizer: ocr),
        );
        await tester.pumpAndSettle();
        await tapText(tester, 'Etiket tara');
        await tapText(tester, 'Galeriden seç');
        await tapText(tester, 'Fotoğrafı düzenle');
        expect(find.text('Orijinal fotoğraf'), findsOneWidget);
        final handle = find.byKey(const ValueKey('crop-bottom-right'));
        await tester.ensureVisible(handle);
        await tester.drag(handle, const Offset(-35, -25));
        await tester.pumpAndSettle();
        await tapText(tester, '90° sağa');
        await tapText(tester, '90° sola');
        await tapText(tester, 'Sıfırla');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(find.byKey(const ValueKey('crop-left')), '10');
        await tester.enterText(find.byKey(const ValueKey('crop-width')), '80');
        await tapText(tester, 'Kırpmayı uygula');
        expect(photos.edits.last.edit.left, .1);
        expect(photos.edits.last.edit.width, .8);
        expect(photos.edits.last.edit.quarterTurns, 0);
        await tapText(tester, 'Tekrar düzenle');
        await tapText(tester, '90° sağa');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(photos.edits, hasLength(1));
        await tapText(tester, 'Fotoğraftaki metni oku');
        await tapText(tester, 'Metni incele ve düzelt');
        expect(
          photos.released,
          isEmpty,
          reason: 'Editable source stays only in this scan session',
        );
        await tester.enterText(
          find.byKey(const ValueKey('label-text')),
          '80% CO 20% PES',
        );
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
    'return to crop preserves corrected raw text and requires explicit replacement',
    (tester) async {
      final photos = EditingPhotos()..next = editablePhoto('original');
      final ocr = FakeRecognizer();
      await tester.pumpWidget(
        EtiketApp(photoSource: photos, textRecognizer: ocr),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Etiket tara');
      await tapText(tester, 'Galeriden seç');
      await tapText(tester, 'Fotoğraftaki metni oku');
      await tapText(tester, 'Metni incele ve düzelt');
      await tester.enterText(
        find.byKey(const ValueKey('label-text')),
        '80% CO 20% PES',
      );
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Fotoğrafı düzenle');
      await tapText(tester, '90° sağa');
      await tapText(tester, 'Kırpmayı uygula');
      ocr.result = '100% WO';
      await tapText(tester, 'Fotoğraftaki metni oku');
      await tapText(tester, 'Metni incele ve düzelt');
      expect(find.text('Önceki metin değiştirilsin mi?'), findsOneWidget);
      await tapText(tester, 'Metnimi koru');
      await tapText(tester, 'Metin yapıştır');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('label-text')))
            .controller!
            .text,
        '80% CO 20% PES',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'invalid crop stays in editor; cancel/manual and second photo work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final photos = EditingPhotos()..next = editablePhoto('first');
      final ocr = FakeRecognizer();
      await tester.pumpWidget(
        EtiketApp(photoSource: photos, textRecognizer: ocr),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Etiket tara');
      await tapText(tester, 'Galeriden seç');
      await tapText(tester, 'Fotoğrafı düzenle');
      await tester.ensureVisible(find.byKey(const ValueKey('crop-width')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('crop-width')), '0');
      await tapText(tester, 'Kırpmayı uygula');
      expect(find.textContaining('Kırpma alanı'), findsWidgets);
      expect(photos.edits, isEmpty);
      await tapText(tester, 'Düzenlemeyi iptal et');
      photos.next = editablePhoto('second');
      await tapText(tester, 'Başka fotoğraf seç');
      expect(photos.released.map((p) => p.path), contains('first'));
      await tapText(tester, 'Fotoğrafı düzenle');
      final paste = find.descendant(
        of: find.byType(PhotoCropEditor),
        matching: find.text('Metin yapıştır'),
      );
      for (var n = 0; n < 8 && paste.evaluate().isEmpty; n++) {
        // Scroll outside the photo/number fields; dragging the photo edits its crop.
        await tester.dragFrom(const Offset(382, 700), const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(paste);
      await tester.pumpAndSettle();
      await tester.tap(paste);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('label-text')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
