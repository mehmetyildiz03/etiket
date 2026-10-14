import 'fabric.dart';

class FabricInsight {
  final String title;
  final String description;
  final bool confirmed;
  const FabricInsight(this.title, this.description, {this.confirmed = false});
}

/// Interprets *fiber composition only*, never claims to measure garment performance.
List<FabricInsight> analyzeGarment(Garment garment, WearPurpose purpose) {
  if (!garment.isValid) {
    throw ArgumentError('Every fabric section must total 100%.');
  }
  final insights = <FabricInsight>[];
  for (final section in garment.sections) {
    final cotton = section.fibers
        .where((f) => f.name == 'Pamuk')
        .fold<int>(0, (s, f) => s + f.percent);
    final polyester = section.fibers
        .where((f) => f.name == 'Polyester')
        .fold<int>(0, (s, f) => s + f.percent);

    insights.add(FabricInsight(
      '${section.name}: bileşim',
      section.fibers.map((f) => '${f.name} %${f.percent}').join(' · '),
      confirmed: true,
    ));

    if (cotton >= 50) {
      insights.add(FabricInsight(
        '${section.name}: nem emme',
        'Pamuk ağırlıklı bu bölüm nem emebilir. Ne kadar hızlı kuruduğu yalnızca elyaf oranıyla belirlenemez.',
      ));
    }
    if (polyester >= 50) {
      insights.add(FabricInsight(
        '${section.name}: kuruma potansiyeli',
        'Polyester genellikle daha az nem emer; ancak gerçek kuruma ve ter transferi kumaş yapısına bağlıdır.',
      ));
    }
  }

  final purposeText = switch (purpose) {
    WearPurpose.summer =>
      'Sıcak havada hava geçirgenliği, kumaş kalınlığı ve örgü yapısı önemlidir. Etiketten kesin serinlik sonucu çıkarılamaz.',
    WearPurpose.sport =>
      'Spor için nem transferi ve kuruma önemlidir; etiket oranları tek başına performans testi değildir.',
    WearPurpose.daily =>
      'Günlük konfor dokunuş, kalıp, kumaş kalınlığı ve kişisel tercihlere göre değişir.',
  };
  insights.add(FabricInsight('Kullanım amacına göre', purposeText));
  insights.add(const FabricInsight(
    'Bilinmeyenler',
    'Kalınlık, gözeneklilik, apre, gerçek dayanıklılık ve cilt tepkisi bu etiketle doğrulanamaz.',
  ));
  return insights;
}
