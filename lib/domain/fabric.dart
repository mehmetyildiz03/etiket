enum WearPurpose { summer, sport, daily }

class FiberEntry {
  final String name;
  final int percent;
  const FiberEntry(this.name, this.percent);

  bool get isValid => name.trim().isNotEmpty && percent > 0 && percent <= 100;
}

class FabricSection {
  final String name;
  final List<FiberEntry> fibers;
  const FabricSection(this.name, this.fibers);

  int get total => fibers.fold<int>(0, (sum, fiber) => sum + fiber.percent);
  bool get isValid =>
      name.trim().isNotEmpty &&
      fibers.isNotEmpty &&
      fibers.every((fiber) => fiber.isValid) &&
      total == 100;
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
