import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/main.dart';
import 'package:etiket/domain/fabric.dart';
import 'package:etiket/ui/doku_result_overview.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('mobile dashboard and navigation at Doku ${width.toInt()}dp', (tester) async {
      tester.view.physicalSize = Size(width, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const EtiketApp());
      await tester.pumpAndSettle();

      expect(find.text('doku.'), findsOneWidget);
      expect(find.text('ÖRNEK ETİKET'), findsOneWidget);
      expect(find.text('Etiket tara'), findsOneWidget);
      expect(find.text('Fotoğraf çek'), findsOneWidget);
      expect(find.text('Galeriden seç'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Geçmiş'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Henüz kayıt yok'), findsOneWidget);
      expect(find.textContaining('Kaydedilen kıyafetler'), findsOneWidget);

      await tester.tap(find.text('Bilgi'));
      await tester.pumpAndSettle();
      expect(find.text('Elyaf hakkında'), findsOneWidget);
      expect(find.text('Pamuk'), findsOneWidget);
      expect(find.text('Polyester'), findsOneWidget);

      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();
      expect(find.text('Ayarlar ve gizlilik'), findsOneWidget);
      expect(find.text('Cihaz içinde görüntü işleme'), findsOneWidget);

      await tester.tap(find.text('Oku'));
      await tester.pumpAndSettle();
      expect(find.text('Etiket tara'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('result separates composition from unrecognized care labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DokuResultOverview(
            garment: sampleGarment,
            sourceConfirmed: false,
            onEdit: () {},
          ),
        ),
      ),
    ));
    expect(find.text('Sonuçlar'), findsOneWidget);
    expect(find.text('%70'), findsOneWidget);
    expect(find.text('%30'), findsOneWidget);
    expect(find.text('Pamuk'), findsOneWidget);
    expect(find.text('Polyester'), findsOneWidget);
    expect(find.text('Bakım talimatları'), findsOneWidget);
    expect(find.textContaining('henüz fotoğraftan güvenilir'), findsOneWidget);
    expect(find.textContaining('orijinal etiketle kontrol'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
