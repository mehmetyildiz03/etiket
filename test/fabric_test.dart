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
}
