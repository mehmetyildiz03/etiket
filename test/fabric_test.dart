import 'package:etiket/domain/analysis.dart';
import 'package:etiket/domain/fabric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each component must independently total 100', () {
    const garment = Garment('Ceket', [
      FabricSection('Dış kumaş', [FiberEntry('Yün', 60), FiberEntry('Polyester', 40)]),
      FabricSection('Astar', [FiberEntry('Viskon', 100)]),
    ]);
    expect(garment.isValid, isTrue);
  });

  test('invalid totals and empty sections are rejected', () {
    const bad = Garment('Test', [
      FabricSection('Ana kumaş', [FiberEntry('Pamuk', 70), FiberEntry('Polyester', 20)]),
    ]);
    expect(bad.isValid, isFalse);
    expect(() => analyzeGarment(bad, WearPurpose.daily), throwsArgumentError);
  });

  test('analysis distinguishes known composition from inference', () {
    final result = analyzeGarment(sampleGarment, WearPurpose.summer);
    expect(result.first.confirmed, isTrue);
    expect(result.skip(1).every((item) => !item.confirmed), isTrue);
    expect(result.last.description, contains('doğrulanamaz'));
  });

  test('three fibers and a separate lining retain their own composition', () {
    const garment = Garment('Ceket', [
      FabricSection('Dış kumaş', [
        FiberEntry('Yün', 60),
        FiberEntry('Polyester', 35),
        FiberEntry('Elastan', 5),
      ]),
      FabricSection('Astar', [FiberEntry('Viskon', 100)]),
    ]);
    expect(garment.isValid, isTrue);
    final confirmed = analyzeGarment(garment, WearPurpose.daily)
        .where((insight) => insight.confirmed)
        .toList();
    expect(confirmed, hasLength(2));
    expect(confirmed[0].title, 'Dış kumaş: bileşim');
    expect(confirmed[0].description, 'Yün %60 · Polyester %35 · Elastan %5');
    expect(confirmed[1].title, 'Astar: bileşim');
    expect(confirmed[1].description, 'Viskon %100');
  });

  test('section totals cannot compensate for each other', () {
    const garment = Garment('Ceket', [
      FabricSection('Dış kumaş', [FiberEntry('Yün', 90)]),
      FabricSection('Astar', [
        FiberEntry('Viskon', 60),
        FiberEntry('Polyester', 50),
      ]),
    ]);
    expect(garment.sections.map((section) => section.total), [90, 110]);
    expect(garment.isValid, isFalse);
    expect(() => analyzeGarment(garment, WearPurpose.daily), throwsArgumentError);
  });

  test('empty garments, sections and blank names are rejected', () {
    const invalid = [
      Garment('Boş', []),
      Garment('Boş bölüm', [FabricSection('Ana kumaş', [])]),
      Garment('Adsız bölüm', [FabricSection('  ', [FiberEntry('Pamuk', 100)])]),
      Garment('Adsız elyaf', [FabricSection('Ana kumaş', [FiberEntry(' ', 100)])]),
    ];
    for (final garment in invalid) {
      expect(garment.isValid, isFalse, reason: garment.title);
      expect(() => analyzeGarment(garment, WearPurpose.daily), throwsArgumentError);
    }
  });

  test('invalid fiber percentages fail even when the section totals 100', () {
    for (final percent in [-1, 0, 101]) {
      final section = FabricSection('Ana kumaş', [
        FiberEntry('Pamuk', percent),
        FiberEntry('Polyester', 100 - percent),
      ]);
      expect(section.total, 100);
      expect(section.isValid, isFalse);
    }
  });

  test('each purpose produces the relevant qualified explanation', () {
    const expected = {
      WearPurpose.summer: 'kesin serinlik sonucu çıkarılamaz',
      WearPurpose.sport: 'performans testi değildir',
      WearPurpose.daily: 'kişisel tercihlere göre değişir',
    };
    for (final entry in expected.entries) {
      final insight = analyzeGarment(sampleGarment, entry.key)
          .singleWhere((insight) => insight.title == 'Kullanım amacına göre');
      expect(insight.confirmed, isFalse);
      expect(insight.description, contains(entry.value));
    }
  });
}
