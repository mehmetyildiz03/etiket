import 'package:flutter/material.dart';

const dokuGreen = Color(0xFF254A3F);
const dokuCream = Color(0xFFF4F2EC);
const dokuSage = Color(0xFFDEE8DC);

/// Non-photographic example illustration: it is NEVER a user scan or OCR proof.
class DokuHomeDashboard extends StatelessWidget {
  const DokuHomeDashboard({
    super.key,
    required this.onScan,
    required this.onCamera,
    required this.onGallery,
    required this.onManual,
    required this.onPaste,
  });

  final VoidCallback onScan;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onManual;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'doku.',
                style: TextStyle(
                  fontSize: 42,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: dokuGreen,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Kumaş etiketini fotoğraflayın\nve içeriğini öğrenin.',
              textAlign: TextAlign.center,
              style: heading.titleMedium?.copyWith(
                color: const Color(0xFF272F2C),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            const _LabelIllustration(),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const ValueKey('home-scan'),
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Etiket tara'),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Fotoğraf çek'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeriden seç'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onManual,
              icon: const Icon(Icons.edit_note),
              label: const Text('Elle kumaş bilgisi gir'),
            ),
            TextButton.icon(
              onPressed: onPaste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Etiket metnini yapıştır'),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 15, color: dokuGreen),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Fotoğraflar cihazında işlenir · Üyelik gerekmez',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: dokuGreen),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _LabelIllustration extends StatelessWidget {
  const _LabelIllustration();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Örnek kumaş etiketi illüstrasyonu; gerçek tarama değildir',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: SizedBox(
          height: 285,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF91A99A),
                        Color(0xFF45675A),
                        Color(0xFF183B32),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -86,
                left: -48,
                child: Transform.rotate(
                  angle: -.34,
                  child: Container(
                    width: 215,
                    height: 365,
                    decoration: BoxDecoration(
                      color: const Color(0x66BBCABC),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -95,
                right: -30,
                child: Transform.rotate(
                  angle: .45,
                  child: Container(
                    width: 260,
                    height: 250,
                    decoration: BoxDecoration(
                      color: const Color(0x5530473B),
                      borderRadius: BorderRadius.circular(80),
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: CustomPaint(painter: _ScanCornerPainter()),
              ),
              Transform.rotate(
                angle: -.06,
                child: Container(
                  width: 186,
                  height: 209,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5EC),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 20,
                        offset: Offset(4, 8),
                      ),
                    ],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '60% Polyester',
                        style: TextStyle(
                          color: Color(0xFF2B302C),
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '40% Cotton',
                        style: TextStyle(
                          color: Color(0xFF2B302C),
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 16),
                      Divider(color: Color(0xFFBFC8BB)),
                      SizedBox(height: 5),
                      Text(
                        'ÖRNEK ETİKET',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Color(0xFF56635C),
                        ),
                      ),
                      Spacer(),
                      Text(
                        'Etikete bakarak doğrula',
                        style: TextStyle(fontSize: 10, color: Color(0xFF56635C)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanCornerPainter extends CustomPainter {
  const _ScanCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8F2E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const length = 26.0;
    final left = size.width / 2 - 128;
    final right = size.width / 2 + 128;
    final top = size.height / 2 - 113;
    final bottom = size.height / 2 + 113;
    final path = Path()
      ..moveTo(left, top + length)
      ..lineTo(left, top)
      ..lineTo(left + length, top)
      ..moveTo(right - length, top)
      ..lineTo(right, top)
      ..lineTo(right, top + length)
      ..moveTo(left, bottom - length)
      ..lineTo(left, bottom)
      ..lineTo(left + length, bottom)
      ..moveTo(right - length, bottom)
      ..lineTo(right, bottom)
      ..lineTo(right, bottom - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DokuHistoryEmpty extends StatelessWidget {
  const DokuHistoryEmpty({super.key, required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return _DashboardPage(
      icon: Icons.history,
      title: 'Geçmiş',
      subtitle: 'Kaydedilen kıyafetler burada görünecek.',
      content: const [
        Text(
          'Henüz kayıt yok. Şu an Doku fotoğrafları veya etiket bilgilerini '
          'kalıcı olarak kaydetmiyor; örnek taramaları gerçek geçmiş gibi göstermiyoruz.',
        ),
        SizedBox(height: 12),
        Text(
          'Yerel kayıt ve silme kontrolleri hazırlanıyor. '
          'Yeni kayıt özelliği gelene kadar fotoğrafların gizliliği korunur.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
      buttonLabel: 'Etiket tara',
      onPressed: onScan,
    );
  }
}

class DokuPrivacySettings extends StatelessWidget {
  const DokuPrivacySettings({super.key});
  @override
  Widget build(BuildContext context) {
    return const _DashboardPage(
      icon: Icons.shield_outlined,
      title: 'Ayarlar ve gizlilik',
      subtitle: 'Görüntülerinizin ve etiket bilgilerinizin kontrolü sizde.',
      content: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.phone_iphone_outlined, color: dokuGreen),
          title: Text('Cihaz içinde görüntü işleme'),
          subtitle: Text(
            'Web OCR tarayıcıda, native OCR cihazda çalışır; '
            'etiket fotoğrafı OCR sunucusuna gönderilmez.',
          ),
        ),
        Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.cloud_off_outlined, color: dokuGreen),
          title: Text('Üyelik ve bulut hesabı yok'),
          subtitle: Text(
            'İlk kez kullanırken OCR motoru ve dil modelleri internetten indirilebilir.',
          ),
        ),
        Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.report_outlined, color: dokuGreen),
          title: Text('Okuma sonuçları kesin değildir'),
          subtitle: Text(
            'Yüzde oranlarını etiketten karşılaştırıp açıkça doğrulamanız gerekir. '
            'Bakım sembolleri bu sürümde otomatik tespit edilmiyor.',
          ),
        ),
      ],
    );
  }
}

class DokuFiberLibrary extends StatelessWidget {
  const DokuFiberLibrary({super.key});

  static const facts = <(String, String, String)>[
    (
      'Pamuk',
      'Bitkisel selüloz lifi',
      'Pamuk nemi emebilir. Kumaşın nefes alabilirliği, yumuşaklığı ve '
          'kuruma hızı yalnız pamuk oranından belirlenemez.',
    ),
    (
      'Polyester',
      'Sentetik lif',
      'Polyester lifinin nem geri kazanımı genellikle düşüktür. '
          'Gerçek ter transferi ve rahatlık örgü/dokuma yapısına bağlıdır.',
    ),
    (
      'Keten',
      'Bitkisel selüloz lifi',
      'Keten giysilerde serin his mümkün olabilir. '
          'Ancak kumaş kalınlığı ve işlenme biçimi sonucu değiştirir.',
    ),
    (
      'Viskon',
      'Yeniden oluşturulmuş selüloz lifi',
      'Viskonun dökümlülüğü ve nem davranışı üretime göre değişebilir; '
          'kumaşın dayanıklılığı etiketteki elyaf adıyla ölçülemez.',
    ),
    (
      'Yün',
      'Hayvansal protein lifi',
      'Yün nem ile etkileşebilir ve ısı yalıtımına katkıda bulunabilir. '
          'Hassas ciltte his ve bakım gereksinimleri ürüne göre değişir.',
    ),
    (
      'İpek',
      'Hayvansal protein lifi',
      'İpeğin dokunuşu ve dökümü ürün yapısına bağlıdır. '
          'Yıkama ve ütü için yalnızca gerçek bakım etiketini takip edin.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            const Text(
              'Elyaf hakkında',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: dokuGreen,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Etiketin bildirdiği içerik ile kumaşın gerçek performansı farklı şeylerdir.',
              style: TextStyle(height: 1.4, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            for (final fact in facts)
              Card(
                margin: const EdgeInsets.only(bottom: 11),
                child: ExpansionTile(
                  title: Text(
                    fact.$1,
                    style: const TextStyle(
                      color: dokuGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(fact.$2),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  children: [
                    Text(fact.$3, style: const TextStyle(height: 1.5)),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Hava geçirgenliği, ter transferi, doku, kalınlık ve dayanıklılık '
                'yalnız elyaf yüzdelerinden kesin olarak hesaplanamaz. '
                'Bunlar genel bilgilerdir; doğrulanmış giysi test sonuçları değildir.',
                style: TextStyle(color: Colors.black54, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> content;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Icon(icon, size: 40, color: dokuGreen),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: dokuGreen,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(height: 1.5, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ),
            if (onPressed != null && buttonLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
