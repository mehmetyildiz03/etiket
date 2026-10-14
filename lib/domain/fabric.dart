enum WearPurpose { summer, sport, daily }

class FiberEntry {
  final String name;
  final num percent;
  const FiberEntry(this.name, this.percent);

  bool get isValid => name.trim().isNotEmpty && percentageUnits(percent) != null;
}

class FabricSection {
  final String name;
  final List<FiberEntry> fibers;
  const FabricSection(this.name, this.fibers);

  num get total => fibers.fold<num>(0, (sum, fiber) => sum + fiber.percent);
  bool get isValid =>
      name.trim().isNotEmpty &&
      fibers.isNotEmpty &&
      fibers.every((fiber) => fiber.isValid) &&
      fibers.fold<int>(0, (sum, fiber) => sum + (percentageUnits(fiber.percent) ?? 0)) == 10000;
}

class Garment {
  final String title;
  final List<FabricSection> sections;
  const Garment(this.title, this.sections);

  bool get isValid =>
      sections.isNotEmpty &&
      sections.every((section) => section.isValid);
}

const knownFibers = <String>[
  'Pamuk', 'Polyester', 'Keten', 'Viskon', 'Modal', 'Liyosel',
  'Yün', 'İpek', 'Poliamid', 'Elastan', 'Akrilik', 'Asetat',
  'Kaşmir', 'Bambu viskon', 'Diğer'
];

const sampleGarment = Garment('Örnek tişört', [
  FabricSection('Ana kumaş', [
    FiberEntry('Pamuk', 70),
    FiberEntry('Polyester', 30),
  ]),
]);

/// Hundredths avoid floating point totals accepting/rejecting the wrong ratio.
/// Values are not rounded into validity: more than two decimals are rejected.
int? percentageUnits(num value) {
  if (!value.isFinite || value <= 0 || value > 100) {
    return null;
  }
  final scaled = value * 100;
  final units = scaled.round();
  return (scaled - units).abs() < 0.00000001 ? units : null;
}

num? parsePercentage(String text) {
  final value = text.trim();
  if (!RegExp(r'^[+-]?\d+(?:[.,]\d{1,2})?$').hasMatch(value)) {
    return null;
  }
  final parsed = num.tryParse(value.replaceAll(',', '.'));
  return parsed != null && percentageUnits(parsed) != null ? parsed : null;
}

String formatPercentage(num value) => value.toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');
