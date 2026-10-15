import 'package:flutter/material.dart';
import '../scan/ocr_observation.dart';

/// Raw engine evidence is constructed in the tree only after explicit opt-in.
/// It is never copied into the parser, draft, or clipboard automatically.
class OcrDiagnostics extends StatefulWidget {
  const OcrDiagnostics({super.key, required this.observation});
  final OcrObservation observation;
  @override
  State<OcrDiagnostics> createState() => _OcrDiagnosticsState();
}

class _OcrDiagnosticsState extends State<OcrDiagnostics> {
  bool showing = false;
  @override
  void didUpdateWidget(OcrDiagnostics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.observation, widget.observation)) showing = false;
  }

  @override
  Widget build(BuildContext context) {
    final observation = widget.observation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => showing = !showing),
          icon: Icon(
            showing ? Icons.visibility_off_outlined : Icons.info_outline,
          ),
          label: Text(
            showing
                ? 'Ham OCR metnini gizle'
                : "OCR'nin okuduğu ham metni göster",
          ),
        ),
        if (showing) ...[
          const SizedBox(height: 12),
          const Text(
            'Ham OCR çıktısı — doğrulanmış kumaş bileşimi değildir',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bu çıktı kumaş bileşimi olarak doğrulanmadı. Metin hatalı olabilir; yüzde ve elyaf tahmin edilmez. Dokudan kaynaklanan hayali harfler de içerebilir.',
          ),
          const SizedBox(height: 8),
          Text('Etiket kararı: ${observation.decisionLabel}'),
          Text(
            observation.confidence == null
                ? 'Motor güven puanı: mevcut değil.'
                : 'Motor güven puanı: ${observation.confidence!.toStringAsFixed(1)} / 100',
          ),
          const Text(
            'Bu puan, metnin doğru olma olasılığı veya kumaşın güvenilirlik puanı değildir.',
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.primary),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: observation.rawText.isEmpty
                  ? const Text('Motor boş metin döndürdü.')
                  : SelectableText(
                      observation.rawText,
                      key: const ValueKey('raw-ocr-diagnostic'),
                    ),
            ),
          ),
          if (observation.secondReading != null) ...[
            const SizedBox(height: 16),
            const Text(
              'İkinci OCR denemesi — alternatif okuma, doğrulanmamış',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aynı fotoğraf farklı metin bölümlendirme yöntemiyle yeniden okundu. '
              'İki sonuç çelişebilir; uygulama rakamları veya elyafları otomatik seçmez. '
              'Güven puanı doğru olma olasılığı değildir.',
            ),
            const SizedBox(height: 8),
            Text(observation.secondReading!.confidence == null
                ? 'İkinci okuma güven puanı: mevcut değil.'
                : 'İkinci okuma güven puanı: '
                  '${observation.secondReading!.confidence!.toStringAsFixed(1)} / 100'),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  observation.secondReading!.rawText,
                  key: const ValueKey('second-ocr-diagnostic'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Metni seçerek kopyalayabilir, Metin yapıştır veya Elle giriş ile kendin düzenleyebilirsin. Ayrıştırma ve etiketle karşılaştırıp onaylama yine gerekir.',
          ),
        ],
      ],
    );
  }
}
