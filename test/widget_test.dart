import 'package:etiket/domain/fabric.dart';
import 'package:etiket/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder field(String label) => find.ancestor(
      of: find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == label,
      ),
      matching: find.byType(TextFormField),
    );

Future<void> launch(WidgetTester tester, {Size size = const Size(800, 1400)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const EtiketApp());
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  // Let the viewport relayout after scrolling, especially with the soft keyboard open.
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

FilledButton continueButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Devam et'),
    );

void main() {
  testWidgets('keeps the dark green and off-white mobile theme', (tester) async {
    await launch(tester, size: const Size(390, 844));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.colorScheme.primary, const Color(0xFF254A3F));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F2EC));
    expect(find.text('Etiket tara'), findsOneWidget);
    expect(find.text('Elle kumaş bilgisi gir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sample scan reaches a qualified fabric analysis', (tester) async {
    await launch(tester);
    await tapText(tester, 'Etiket tara');
    expect(find.text('ÖRNEK ETİKET'), findsOneWidget);
    await tapText(tester, 'Örnek etiketle devam et');
    expect(find.text('Toplam: %100'), findsOneWidget);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Spor yaparken');
    expect(tester.widget<RadioGroup<WearPurpose>>(
      find.byType(RadioGroup<WearPurpose>),
    ).groupValue, WearPurpose.sport);
    await tapText(tester, 'Analizi göster');
    expect(find.text('Kumaş analizi'), findsOneWidget);
    expect(find.text('Pamuk %70 · Polyester %30'), findsOneWidget);
    expect(find.textContaining('performans testi değildir'), findsOneWidget);
    expect(find.text('KONTROL EDİLEN ETİKET BİLGİSİ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual entry blocks invalid percentages and recovers', (tester) async {
    await launch(tester);
    await tapText(tester, 'Elle kumaş bilgisi gir');
    expect(continueButton(tester).onPressed, isNotNull);
    for (final invalid in ['69', '0', '-1', '101', 'abc', '']) {
      await tester.enterText(field('Yüzde').first, invalid);
      await tester.pump();
      expect(continueButton(tester).onPressed, isNull, reason: invalid);
    }
    await tester.enterText(field('Yüzde').first, '70');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('renaming a section preserves focus and text editing state', (tester) async {
    await launch(tester);
    await tapText(tester, 'Elle kumaş bilgisi gir');
    final name = field('Bölüm adı');
    await tester.showKeyboard(name);
    final before = tester.state(find.descendant(
      of: name,
      matching: find.byType(EditableText),
    ));
    await tester.enterText(name, 'Dış kumaş');
    await tester.pump();
    final editable = find.descendant(of: name, matching: find.byType(EditableText));
    expect(tester.state(editable), same(before));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(name, ' ');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);
    await tester.enterText(name, 'Dış kumaş');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('removing a fiber retains the surviving percentage', (tester) async {
    await launch(tester);
    await tapText(tester, 'Elle kumaş bilgisi gir');
    await tester.tap(find.byTooltip('Elyafı kaldır').first);
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.descendant(
      of: field('Yüzde'),
      matching: find.byType(TextField),
    ));
    expect(input.controller!.text, '30');
    expect(find.text('Toplam: %30'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);
    await tester.enterText(field('Yüzde'), '100');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Polyester %100'), findsOneWidget);
  });

  testWidgets('additional fibers require explicit valid percentages', (tester) async {
    await launch(tester);
    await tapText(tester, 'Elle kumaş bilgisi gir');
    await tapText(tester, 'Elyaf ekle');
    expect(field('Yüzde'), findsNWidgets(3));
    expect(continueButton(tester).onPressed, isNull);
    await tester.enterText(field('Yüzde').at(1), '25');
    await tester.enterText(field('Yüzde').at(2), '5');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNotNull);
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Pamuk %70 · Polyester %25 · Diğer %5'), findsOneWidget);
  });

  testWidgets('separate sections validate independently and survive deletion', (tester) async {
    await launch(tester);
    await tapText(tester, 'Elle kumaş bilgisi gir');
    await tester.enterText(field('Bölüm adı'), 'Dış kumaş');
    await tester.pump();
    await tapText(tester, 'Kumaş bölümü ekle');
    await tester.enterText(field('Bölüm adı').at(1), 'Astar');
    await tester.pump();
    expect(find.text('Toplam: %100'), findsNWidgets(2));
    await tester.enterText(field('Yüzde').at(2), '90');
    await tester.pump();
    expect(continueButton(tester).onPressed, isNull);
    await tester.enterText(field('Yüzde').at(2), '100');
    await tester.pump();
    await tapText(tester, 'Devam et');
    await tapText(tester, 'Analizi göster');
    expect(find.text('Dış kumaş: bileşim'), findsOneWidget);
    expect(find.text('Astar: bileşim'), findsOneWidget);
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bölümü sil').first);
    await tester.pumpAndSettle();
    expect(field('Bölüm adı'), findsOneWidget);
    final input = tester.widget<TextField>(find.descendant(
      of: field('Bölüm adı'),
      matching: find.byType(TextField),
    ));
    expect(input.controller!.text, 'Astar');
    expect(field('Yüzde'), findsOneWidget);
    expect(find.text('Toplam: %100'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
