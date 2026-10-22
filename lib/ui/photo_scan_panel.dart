import 'package:flutter/material.dart';
import 'session_photo_preview.dart';
import 'ocr_diagnostics.dart';
import '../scan/photo_scan.dart';

class PhotoScanPanel extends StatelessWidget {
  const PhotoScanPanel({
    super.key,
    required this.scan,
    required this.onReview,
    required this.onManual,
    required this.onPaste,
    this.onEdit,
  });
  final PhotoScanController scan;
  final VoidCallback onReview;
  final VoidCallback onManual;
  final VoidCallback onPaste;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final photo = scan.photo;
    final presentation = scan.photos is ScanPresentation
        ? scan.photos as ScanPresentation
        : null;
    final progress = scan.recognizer is ScanProgressSource
        ? scan.recognizer as ScanProgressSource
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scan.photos.supported) ...[
          if (presentation?.cameraAvailable ?? true)
            FilledButton.icon(
              onPressed: scan.canPick
                  ? () => scan.pick(PhotoSource.camera)
                  : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Fotoğraf çek'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: scan.canPick
                ? () => scan.pick(PhotoSource.gallery)
                : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(presentation?.galleryLabel ?? 'Galeriden seç'),
          ),
          const SizedBox(height: 12),
          if (presentation != null) ...[
            Text(
              presentation.preparationMessage,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          const Text(
            'Fotoğraf ve etiket metni sunucuya gönderilmez. Fotoğraf yalnızca bu tarama için geçici tutulur.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ] else ...[
          const Text(
            'Bu platformda kamera ve cihaz üzerindeki OCR desteklenmiyor. Metin yapıştırma ve elle giriş kullanılabilir.',
          ),
        ],
        if (photo != null) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SessionPhotoPreview(
              bytes: photo.previewBytes,
              key: const ValueKey('photo-preview'),
              // The Blob points at the exact processed image OCR will read.
              // Safari can paint it natively if Flutter's codec rejects bytes.
              fallbackUrl: photo.path.startsWith('blob:') ? photo.path : null,
              height: 200,
              fit: BoxFit.contain,
              cacheWidth: 960,
              semanticLabel: 'Seçilen etiket fotoğrafı',
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    'Fotoğraf önizlemesi açılamadı. Başka bir fotoğraf seç.',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!scan.busy && scan.stage != ScanStage.ready)
            FilledButton.icon(
              onPressed: scan.recognize,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(
                scan.stage == ScanStage.failed
                    ? 'Tekrar oku'
                    : 'Fotoğraftaki metni oku',
              ),
            ),
        ],
        if (scan.busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              scan.stage == ScanStage.recognizing
                  ? (progress?.progressMessage ?? 'Etiket cihazında okunuyor…')
                  : scan.stage == ScanStage.transforming
                  ? 'Fotoğraf düzenleniyor…'
                  : 'Fotoğraf bekleniyor…',
            ),
          ),
          TextButton.icon(
            onPressed: scan.cancel,
            icon: const Icon(Icons.close),
            label: const Text('İşlemi iptal et'),
          ),
        ],
        if (scan.message != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              scan.message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        if (scan.stage == ScanStage.ready) ...[
          const SizedBox(height: 16),
          const Text(
            'Okunan metin — henüz doğrulanmadı',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(scan.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          if (scan.observation?.candidateWarning != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scan.observation!.candidateWarning!,
                      key: const ValueKey('weak-ocr-warning'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.edit_note),
            label: const Text('Metni incele ve düzelt'),
          ),
          if (scan.canEditPhoto)
            OutlinedButton.icon(
              onPressed: scan.recognize,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden oku'),
            ),
        ],
        if (!scan.busy && scan.observation != null)
          OcrDiagnostics(
            key: ValueKey(scan.revision),
            observation: scan.observation!,
          ),
        if (scan.canEditPhoto) ...[
          OutlinedButton.icon(
            onPressed: scan.busy ? null : onEdit,
            icon: const Icon(Icons.crop_rotate),
            label: Text(
              scan.appliedEdit == null ? 'Fotoğrafı düzenle' : 'Tekrar düzenle',
            ),
          ),
          OutlinedButton.icon(
            onPressed: scan.canPick
                ? () => scan.pick(PhotoSource.gallery)
                : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Başka fotoğraf seç'),
          ),
          const Text(
            'Bu önizlemedeki görüntü OCR’ye gönderilir. Kırpma isteğe bağlıdır.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste),
          label: const Text('Metin yapıştır'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.edit_note),
          label: const Text('Elle giriş'),
        ),
      ],
    );
  }
}
