import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show continueButton, field, launch, tapText;

Finder get labelInput => find.byKey(const ValueKey('label-text'));

Future<void> preview(WidgetTester tester, String text) async {
  await tester.enterText(labelInput, text);
  await tapText(tester, 'Metni ayrıştır');
}

Future<void> review(WidgetTester tester) async {
  await tapText(tester, 'Etiketle karşılaştırdım ve doğruladım');
}

void main() {
  testWidgets('pasted text must be reviewed before a confirmed analysis', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, 'Shell: 70% CO 30% PES\nLining: 100% VI');
    expect(find.text('Ayrıştırma önerisi'), findsOneWidget);
    expect(find.text('Henüz doğrulanmadı'), findsOneWidget);
    await tapText(tester, 'Düzenleyicide incele');
    expect(continueButton(tester).onPressed, isNull);
    await review(tester);
    expect(continueButton(tester).onPressed, isNotNull);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Dış kumaş: bileşim'), findsOneWidget);
    expect(find.text('Astar: bileşim'), findsOneWidget);
    expect(find.text('Pamuk %70 · Polyester %30'), findsOneWidget);
    expect(find.text('Viskon %100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown fiber and missing percentage remain editable', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, '70% CO\nmystery fiber');
    expect(find.textContaining('Elyaf tanınmadı'), findsWidgets);
    await tapText(tester, 'Düzenleyicide incele');
    expect(continueButton(tester).onPressed, isNull);
    final input = tester.widget<TextField>(find.descendant(
      of: field('Yüzde').last,
      matching: find.byType(TextField),
    ));
    expect(input.controller!.text, isEmpty);
    final dropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polyester').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Yüzde').last, '30');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);
    await review(tester);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Pamuk %70 · Polyester %30'), findsOneWidget);
  });

  testWidgets('reparsing or cancelling cannot erase user corrections', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, '70% CO 30% PES');
    await tapText(tester, 'Düzenleyicide incele');
    await tester.enterText(field('Yüzde').first, '80');
    await tester.enterText(field('Yüzde').last, '20');
    await tester.pump();
    await tapText(tester, 'Başka metin ayrıştır');
    await preview(tester, '100% WO');
    await tapText(tester, 'Düzenleyicide incele');
    expect(find.text('Mevcut düzenlemeler değiştirilsin mi?'), findsOneWidget);
    await tapText(tester, 'Düzenlemeleri koru');
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.descendant(
      of: field('Yüzde').first,
      matching: find.byType(TextField),
    ));
    expect(input.controller!.text, '80');
    await review(tester);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Pamuk %80 · Polyester %20'), findsOneWidget);
  });

  testWidgets('replacement is explicit and edits revoke source confirmation', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, '100% wool');
    await tapText(tester, 'Düzenleyicide incele');
    await review(tester);
    expect(continueButton(tester).onPressed, isNotNull);
    await tester.enterText(field('Bölüm adı'), 'Dış kumaş');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);
    await tapText(tester, 'Başka metin ayrıştır');
    await preview(tester, '100% CO');
    await tapText(tester, 'Düzenleyicide incele');
    await tapText(tester, 'Yeni metni kullan');
    expect(field('Yüzde'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);
    await review(tester);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Pamuk %100'), findsOneWidget);
  });

  testWidgets('decimal percentages are preserved through manual correction', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, '70,5% CO 29,5% PES');
    await tapText(tester, 'Düzenleyicide incele');
    await tester.enterText(field('Yüzde').first, '70,25');
    await tester.enterText(field('Yüzde').last, '29.75');
    await tester.pump();
    expect(find.text('Toplam: %100'), findsOneWidget);
    await review(tester);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Pamuk %70,25 · Polyester %29,75'), findsOneWidget);
  });

  testWidgets('small screen, open keyboard, empty input and back stay usable', (tester) async {
    await launch(tester, size: const Size(390, 844));
    await tapText(tester, 'Etiket metnini yapıştır');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await preview(tester, ' \n ');
    expect(find.text('Etiket metni boş. Metni yapıştırın veya elle giriş yapın.'), findsOneWidget);
    expect(find.text('Düzenleyicide incele'), findsNothing);
    await preview(tester, '7O% cotton');
    expect(find.textContaining('Yüzde okunamadı'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    expect(find.text('Etiket tara'), findsOneWidget);
  });

  testWidgets('small-screen editing and system back preserve corrections', (tester) async {
    await launch(tester, size: const Size(390, 844));
    await tapText(tester, 'Etiket metnini yapıştır');
    await preview(tester, '70% CO 30% PES');
    await tapText(tester, 'Düzenleyicide incele');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(field('Yüzde').first, '75');
    await tester.enterText(field('Yüzde').last, '25');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(labelInput, findsOneWidget);
    await tapText(tester, 'Metni ayrıştır');
    await tapText(tester, 'Düzenleyicide incele');
    await tapText(tester, 'Düzenlemeleri koru');
    // Return to the editor without applying the older parsed percentages.
    await tapText(tester, 'Elle girişe dön');
    final input = tester.widget<TextField>(find.descendant(
      of: field('Yüzde').first,
      matching: find.byType(TextField),
    ));
    expect(input.controller!.text, '75');
    expect(continueButton(tester).onPressed, isNull);
    await review(tester);
    expect(continueButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
