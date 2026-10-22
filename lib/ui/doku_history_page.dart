import 'package:flutter/material.dart';
import '../history/local_history.dart';
import '../domain/fabric.dart';
import 'doku_mobile_shell.dart';
import 'doku_result_overview.dart';

class DokuHistoryPage extends StatelessWidget {
  const DokuHistoryPage({
    super.key, required this.items, required this.isLoading,
    required this.isBusy, required this.error, required this.onScan,
    required this.onOpen, required this.onDelete, required this.onClear,
    required this.onRetry,
  });

  final List<SavedGarment> items;
  final bool isLoading;
  final bool isBusy;
  final String? error;
  final VoidCallback onScan;
  final ValueChanged<SavedGarment> onOpen;
  final ValueChanged<SavedGarment> onDelete;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Geçmiş',
            style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: dokuGreen)),
          const SizedBox(height: 8),
          const Text(
            'Yalnız senin kaydettiğin kıyafetler bu cihazda saklanır. '
            'Fotoğraflar ve ham OCR metinleri geçmişe eklenmez.',
            style: TextStyle(height: 1.45),
          ),
          const SizedBox(height: 8),
          const Text('Kaydedilen kıyafetler burada görünecek.'),
          const SizedBox(height: 18),
          if (isLoading) const Center(child: CircularProgressIndicator())
          else if (error != null) ...[
            const Text('Geçmiş yüklenemedi. Kayıtlar korunuyor; silme veya üzerine yazma yapılmadı.',
              style: TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            TextButton.icon(onPressed: isBusy ? null : onRetry,
              icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
          ] else if (items.isEmpty) ...[
            const Card(child: Padding(
              padding: EdgeInsets.all(22),
              child: Column(children: [
                Icon(Icons.inventory_2_outlined, color: dokuGreen, size: 44),
                SizedBox(height: 12),
                Text('Henüz kayıt yok', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('İlk analizini doğrulayıp sonuç ekranında Kaydet seçeneğini kullan.'),
              ]),
            )),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Etiket tara')),
          ] else ...[
            Text('${items.length} kıyafet kayıtlı',
              style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            for (final item in items)
              Card(
                key: ValueKey('saved-${item.id}'),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const Icon(Icons.checkroom_outlined, color: dokuGreen),
                  title: Text(item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    item.garment.sections.map((s) => s.fibers.map((f) =>
                      '%${formatPercentage(f.percent)} ${f.name}').join(', ')).join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: isBusy ? null : () => onOpen(item),
                  trailing: IconButton(
                    tooltip: 'Kaydı sil',
                    onPressed: isBusy ? null : () => onDelete(item),
                    icon: const Icon(Icons.delete_outline)),
                ),
              ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: isBusy ? null : onClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Tüm geçmişi sil')),
          ],
        ],
      ),
    ),
  );
}

class DokuSavedDetail extends StatelessWidget {
  const DokuSavedDetail({super.key, required this.item});
  final SavedGarment item;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(item.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kaynak: ${item.source == 'label' ? 'Etiket kontrol edildi' : 'Elle girildi'}'),
            const SizedBox(height: 14),
            DokuResultOverview(
              garment: item.garment,
              sourceConfirmed: item.source == 'label',
              onEdit: () {},
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Kapat')),
    ],
  );
}
