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
  /// Advisory only: compare printed percent-marked digit sequences in reading
  /// order. Never infer missing ratios, match fibers or replace the first OCR.
  bool get percentageTokensDiffer {
    final alternative = secondReading;
    if (alternative == null) return false;
    final primaryTokens = _printedPercentTokens(rawText);
    final alternativeTokens = _printedPercentTokens(alternative.rawText);
    if (primaryTokens.length != alternativeTokens.length) return true;
    for (var i = 0; i < primaryTokens.length; i++) {
      if (primaryTokens[i] != alternativeTokens[i]) return true;
    }
    return false;
  }
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


/// Only explicitly percent-marked numbers; no composition or fiber inference.
/// Compare decimal punctuation and trailing zero formatting conservatively.
/// Never take a partial ratio from an oversized or malformed number.
List<String> _printedPercentTokens(String text) {
  final matches = RegExp(
    r'[0-9]{1,3}(?:[.,][0-9]{1,2})?[ \t]*[%％]|'
    r'[%％][ \t]*[0-9]{1,3}(?:[.,][0-9]{1,2})?',
  ).allMatches(text);
  final digit = RegExp(r'[0-9]');
  return matches.where((match) {
    final before = match.start > 0 ? text[match.start - 1] : '';
    final after = match.end < text.length ? text[match.end] : '';
    final partialLeft = digit.hasMatch(before) ||
        ((before == '.' || before == ',') &&
            match.start > 1 &&
            digit.hasMatch(text[match.start - 2]));
    final partialRight = digit.hasMatch(after) ||
        ((after == '.' || after == ',') &&
            match.end + 1 < text.length &&
            digit.hasMatch(text[match.end + 1]));
    return !partialLeft && !partialRight;
  }).map((match) {
    final value = match.group(0)!
        .replaceAll(RegExp(r'[%％ \t]'), '')
        .replaceAll(',', '.');
    final separator = value.indexOf('.');
    if (separator < 0) return value;
    final whole = value.substring(0, separator);
    final fraction =
        value.substring(separator + 1).replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? whole : '${whole}.${fraction}';
  }).toList(growable: false);
}
