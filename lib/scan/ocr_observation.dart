/// Only a proposal. Neither model confidence nor this policy decision verifies
/// fiber percentages. No parser, Flutter or native OCR dependency lives here.
enum OcrDecision { noText, lowConfidence, noComposition, candidate }

/// Independent Tesseract output, *not* a corrected transcription or a draft.
class OcrSecondReading {
  OcrSecondReading({required this.rawText, required this.confidence}) {
    if (rawText.length > 20000 ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 100))) {
      throw ArgumentError('Invalid secondary OCR reading');
    }
  }
  final String rawText;
  final double? confidence;
}

class OcrObservation {
  OcrObservation({
    required this.rawText,
    required this.confidence,
    required this.decision,
    this.secondReading,
  }) {
    if (rawText.length > 20000 ||
        (confidence != null &&
            (!confidence!.isFinite || confidence! < 0 || confidence! > 100)) ||
        (decision == OcrDecision.candidate &&
            (rawText.trim().isEmpty ||
                confidence == null ||
                confidence! < 45))) {
      throw ArgumentError('Invalid OCR observation');
    }
  }
  final String rawText;
  final double? confidence;
  final OcrDecision decision;
  final OcrSecondReading? secondReading;
  String? get acceptedText =>
      decision == OcrDecision.candidate ? rawText : null;
  /// Accepted OCR text remains editable, but a marginal engine score must
  /// not be mistaken for a reliable transcription. No automatic correction.
  bool get weakCandidate =>
      decision == OcrDecision.candidate &&
      confidence != null &&
      confidence! < 65;
  String? get candidateWarning => weakCandidate
      ? 'Düşük OCR güveni (${confidence!.toStringAsFixed(1)}/100). '
        'Okunan yüzde işaretleri, rakamlar ve elyaf adları yanlış olabilir. '
        'Lütfen etiket fotoğrafıyla karşılaştırıp düzelt. '
        'Bu puan doğruluk olasılığı değildir.'
      : null;
  String get explanation => switch (decision) {
    OcrDecision.noText =>
      'OCR motoru bu fotoğrafta okunabilir bir metin çıkaramadı. Daha net bir fotoğraf deneyebilir veya elle giriş yapabilirsin.',
    OcrDecision.lowConfidence =>
      'Okunan yazı düşük güvenilirlikte; etikete bakarak kontrol et. Çıktı, kumaş dokusundan kaynaklanan hatalı harfler içerebilir.',
    OcrDecision.noComposition =>
      'Yazı algılandı, ancak kumaş bileşimi tespit edilemedi. Metin hatalı olabilir; fotoğrafı veya ham çıktıyı kontrol edebilirsin.',
    OcrDecision.candidate =>
      'Kumaş bileşimi için aday metin bulundu. Etiketle karşılaştırıp düzeltmen ve doğrulaman gerekiyor.',
  };
  String get decisionLabel => switch (decision) {
    OcrDecision.noText => 'Okunabilir metin çıkarılamadı',
    OcrDecision.lowConfidence => 'Güven yetersiz — etiket adayı kabul edilmedi',
    OcrDecision.noComposition =>
      'Kumaş bileşimi bulunamadı — etiket adayı kabul edilmedi',
    OcrDecision.candidate => 'Etiket adayı — kullanıcı doğrulaması bekliyor',
  };
}
