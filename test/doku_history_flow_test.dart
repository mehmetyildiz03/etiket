import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/main.dart';
import 'package:etiket/history/local_history.dart';

class InMemoryStore implements HistoryStore {
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String text) async { saved = text; }
}

void main() {
  testWidgets('real user edit can save, reopen after app restart and delete', (tester) async {
    final store=InMemoryStore();
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio=1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(EtiketApp(historyStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etiket tara'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bilgileri elle gir'));
    await tester.tap(find.text('Bilgileri elle gir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('percent-draft-1')), '65');
    await tester.enterText(find.byKey(const ValueKey('percent-draft-2')), '35');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Devam et'));
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Analizi göster'));
    await tester.tap(find.text('Analizi göster'));
    await tester.pumpAndSettle();

    expect(find.text('Kıyafeti kaydet'),findsOneWidget);
    await tester.ensureVisible(find.text('Kıyafeti kaydet'));
    await tester.tap(find.text('Kıyafeti kaydet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last,'Günlük gömlek');
    await tester.tap(find.widgetWithText(FilledButton,'Kaydet'));
    await tester.pumpAndSettle();
    expect(store.saved,contains('Günlük gömlek'));
    expect(store.saved,contains('65'));

    // A new Flutter tree must reconstruct its history from persisted storage.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(EtiketApp(historyStore:store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geçmiş'));
    await tester.pumpAndSettle();
    expect(find.text('Günlük gömlek'),findsOneWidget);
    await tester.tap(find.text('Günlük gömlek'));
    await tester.pumpAndSettle();
    expect(find.text('%65'),findsWidgets);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kaydı sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton,'Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz kayıt yok'),findsOneWidget);
    expect((await LocalHistoryRepository(store).list()),isEmpty);
  });
}
