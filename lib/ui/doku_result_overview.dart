import 'package:flutter/material.dart';
import '../domain/fabric.dart';
import 'doku_mobile_shell.dart';

/// A readable result summary. Care symbols are not recognized by text OCR.
class DokuResultOverview extends StatelessWidget {
  const DokuResultOverview({
    super.key,
    required this.garment,
    required this.sourceConfirmed,
    required this.onEdit,
  });

  final Garment garment;
  final bool sourceConfirmed;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sonuçlar',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: dokuGreen,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sourceConfirmed
              ? 'Etiketle karşılaştırılarak doğrulanan bileşim.'
              : 'Girilen kumaş bileşimi. Bilgileri orijinal etiketle kontrol edin.',
          style: const TextStyle(height: 1.5, color: Colors.black87),
        ),
        const SizedBox(height: 17),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Kumaş bileşimi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: dokuGreen,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Düzenle'),
                    ),
                  ],
                ),
                for (final section in garment.sections) ...[
                  const SizedBox(height: 10),
                  Text(
                    section.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final fiber in section.fibers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            constraints: const BoxConstraints(minWidth: 70),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: dokuSage,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              '%${formatPercentage(fiber.percent)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: dokuGreen,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fiber.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_laundry_service_outlined, color: dokuGreen),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bakım talimatları',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: dokuGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 9),
                Text(
                  'Bakım sembolleri henüz fotoğraftan güvenilir biçimde '
                  'tespit edilmiyor. Bu nedenle bu giysiye ait yıkama, '
                  'kurutma veya ütü sıcaklığı uydurulmuyor. '
                  'Lütfen orijinal bakım etiketini takip edin.',
                  style: TextStyle(height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Kumaş analizi',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: dokuGreen,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Aşağıdaki yorumlar ölçülmüş giysi performansı değil, '
          'elyaf türlerine ilişkin genel bilgilerdir.',
          style: TextStyle(
            color: Colors.black54,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
