import 'dart:typed_data';
import 'photo_scan.dart';

class BrowserPhoto {
  BrowserPhoto(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
}

class BrowserScanException implements Exception {
  const BrowserScanException(this.code);
  final String code;
}

/// Narrow, testable contract; JS objects never enter the parser or draft.
abstract interface class BrowserScanBridge {
  bool get supported;
  bool get cameraAvailable;
  Future<BrowserPhoto?> pick(bool camera);
  Future<String> recognize(String path, void Function(String) progress);
  void release(String path);
  void cancelRecognition();
  void cancelSelection();
  void dispose();
}

ScanFailure _failure(Object error) => ScanFailure(switch (error) {
  BrowserScanException(code: 'permission') => ScanFailureKind.permission,
  BrowserScanException(code: 'unavailableCamera') =>
    ScanFailureKind.unavailableCamera,
  BrowserScanException(code: 'tooLarge') => ScanFailureKind.tooLarge,
  BrowserScanException(code: 'invalidPhoto') => ScanFailureKind.invalidPhoto,
  BrowserScanException(code: 'emptyText') => ScanFailureKind.emptyText,
  BrowserScanException(code: 'unsupported') => ScanFailureKind.unsupported,
  BrowserScanException(code: 'modelLoad') => ScanFailureKind.modelLoad,
  BrowserScanException(code: 'tooMuchText') => ScanFailureKind.tooMuchText,
  _ => ScanFailureKind.recognition,
});

class WebPhotoSource
    implements PhotoSourceService, ScanPresentation, DisposablePhotoSource {
  WebPhotoSource(this.bridge);
  final BrowserScanBridge bridge;
  @override
  bool get supported => bridge.supported;
  @override
  bool get cameraAvailable => bridge.cameraAvailable;
  @override
  String get galleryLabel => 'Fotoğraf yükle / galeriden seç';
  @override
  String get preparationMessage =>
      'Tarayıcı OCR’si ilk okumada yaklaşık 9 MB motor ve Türkçe/İngilizce model indirir; internet gerekir ve biraz sürebilir. '
      'Sonraki okumalar daha hızlıdır. Kamera seçeneği destekleyen mobil tarayıcının sistem seçicisini açar. '
      'Fotoğraf yükleme her zaman alternatifidir. JPG, PNG veya WebP; en fazla 20 MB / 24 milyon piksel.';
  @override
  Future<ScanPhoto?> pick(PhotoSource source) async {
    if (!supported) throw const ScanFailure(ScanFailureKind.unsupported);
    if (source == PhotoSource.camera && !cameraAvailable) {
      throw const ScanFailure(ScanFailureKind.unavailableCamera);
    }
    try {
      final picked = await bridge.pick(source == PhotoSource.camera);
      return picked == null
          ? null
          : ScanPhoto(path: picked.path, previewBytes: picked.bytes);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ScanPhoto?> recover() async => null;
  @override
  Future<void> release(ScanPhoto photo) async => bridge.release(photo.path);
  @override
  void cancelSelection() => bridge.cancelSelection();
  @override
  void disposePhotos() => bridge.dispose();
}

class WebTextRecognizer
    implements
        TextRecognitionService,
        ScanProgressSource,
        CancelableRecognition {
  WebTextRecognizer(this.bridge);
  final BrowserScanBridge bridge;
  @override
  String? progressMessage;
  @override
  void Function()? onProgress;
  @override
  Future<String> recognize(ScanPhoto photo) async {
    progressMessage = 'OCR motoru hazırlanıyor…';
    try {
      return await bridge.recognize(photo.path, (message) {
        progressMessage = message;
        onProgress?.call();
      });
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  void cancelRecognition() {
    progressMessage = null;
    bridge.cancelRecognition();
  }
}
