import 'dart:async';
import 'dart:typed_data';

enum PhotoSource { camera, gallery }

enum ScanStage {
  idle,
  recovering,
  picking,
  preview,
  recognizing,
  ready,
  failed,
}

enum ScanFailureKind {
  permission,
  unavailableCamera,
  invalidPhoto,
  tooLarge,
  emptyText,
  tooMuchText,
  recognition,
  unsupported,
}

class ScanFailure implements Exception {
  const ScanFailure(this.kind, {this.permanent = false});
  final ScanFailureKind kind;
  final bool permanent;
  String get message => switch (kind) {
    ScanFailureKind.permission =>
      permanent
          ? 'Fotoğraf erişimi kapalı. Telefon ayarlarından izinleri kontrol edebilir veya elle giriş yapabilirsin.'
          : 'Fotoğraf erişimine izin verilmedi. Tekrar deneyebilir veya elle giriş yapabilirsin.',
    ScanFailureKind.unavailableCamera =>
      'Kamera açılamadı. Galeriden seçebilir veya elle giriş yapabilirsin.',
    ScanFailureKind.invalidPhoto =>
      'Fotoğraf okunamadı. Başka bir fotoğraf seç veya metni elle gir.',
    ScanFailureKind.tooLarge =>
      'Fotoğraf çok büyük. Etiketi daha yakından, daha düşük çözünürlükte çek.',
    ScanFailureKind.emptyText =>
      'Fotoğrafta okunabilir yazı bulunamadı. Etiketi aydınlıkta ve net çek veya metni elle gir.',
    ScanFailureKind.tooMuchText =>
      'Fotoğrafta çok fazla metin var. Yalnızca kumaş etiketini kadraja al.',
    ScanFailureKind.recognition =>
      'Etiket okunamadı. Tekrar deneyebilir veya metni elle girebilirsin.',
    ScanFailureKind.unsupported =>
      'Bu platformda kamera ve cihaz üzerindeki OCR desteklenmiyor. Metin yapıştırma ve elle giriş kullanılabilir.',
  };
}

/// Only the source adapter owns the temporary file. The controller never deletes
/// a gallery original or sends an image/text to a server.
class ScanPhoto {
  ScanPhoto({required this.path, required Uint8List previewBytes})
    : previewBytes = previewBytes.asUnmodifiableView();
  final String path;
  final Uint8List previewBytes;
}

abstract interface class PhotoSourceService {
  bool get supported;
  Future<ScanPhoto?> pick(PhotoSource source);
  Future<ScanPhoto?> recover();
  Future<void> release(ScanPhoto photo);
}

abstract interface class TextRecognitionService {
  Future<String> recognize(ScanPhoto photo);
}

class PhotoScanController {
  PhotoScanController(this.photos, this.recognizer);
  final PhotoSourceService photos;
  final TextRecognitionService recognizer;
  void Function()? onChanged;
  ScanStage _stage = ScanStage.idle;
  ScanPhoto? _photo;
  String _text = '';
  String? _message;
  int _revision = 0;
  bool _disposed = false;
  bool _pickerOpen = false;
  final Map<ScanPhoto, int> _inFlight = {};
  final Set<ScanPhoto> _retired = {};
  ScanStage get stage => _stage;
  ScanPhoto? get photo => _photo;
  String get text => _text;
  String? get message => _message;
  bool get canPick => !_disposed && photos.supported && !_pickerOpen;
  bool get busy => {
    ScanStage.picking,
    ScanStage.recovering,
    ScanStage.recognizing,
  }.contains(_stage);
  int get revision => _revision;

  void _notify() {
    if (!_disposed) onChanged?.call();
  }

  bool _current(int revision) => !_disposed && revision == _revision;
  void _fail(Object error, ScanFailureKind fallback) {
    _stage = ScanStage.failed;
    _message = (error is ScanFailure ? error : ScanFailure(fallback)).message;
  }

  Future<void> pick(PhotoSource source) =>
      _select(() => photos.pick(source), recovering: false);
  Future<void> recover() async {
    if (!photos.supported) return;
    await _select(photos.recover, recovering: true);
  }

  Future<void> _select(
    Future<ScanPhoto?> Function() select, {
    required bool recovering,
  }) async {
    if (_disposed || _pickerOpen) return;
    if (!photos.supported) {
      _fail(
        const ScanFailure(ScanFailureKind.unsupported),
        ScanFailureKind.unsupported,
      );
      _notify();
      return;
    }
    final revision = ++_revision;
    _pickerOpen = true;
    _stage = recovering ? ScanStage.recovering : ScanStage.picking;
    _message = null;
    _notify();
    try {
      final selected = await select();
      if (!_current(revision)) {
        if (selected != null) await _retire(selected);
        return;
      }
      if (selected == null) {
        _stage = _photo == null
            ? ScanStage.idle
            : (_text.isEmpty ? ScanStage.preview : ScanStage.ready);
        _message = recovering ? null : 'Fotoğraf seçimi iptal edildi.';
      } else {
        final previous = _photo;
        _photo = selected;
        _text = '';
        _stage = ScanStage.preview;
        if (previous != null && !identical(previous, selected)) {
          await _retire(previous);
        }
      }
    } catch (error) {
      if (_current(revision)) _fail(error, ScanFailureKind.invalidPhoto);
    } finally {
      _pickerOpen = false;
      _notify();
    }
  }

  Future<void> recognize() async {
    if (_disposed) return;
    if (!photos.supported) {
      _fail(
        const ScanFailure(ScanFailureKind.unsupported),
        ScanFailureKind.unsupported,
      );
      _notify();
      return;
    }
    final input = _photo;
    if (input == null || _pickerOpen || _stage == ScanStage.recognizing) return;
    final revision = ++_revision;
    _stage = ScanStage.recognizing;
    _message = null;
    _inFlight[input] = (_inFlight[input] ?? 0) + 1;
    _notify();
    try {
      final recognized = await recognizer.recognize(input);
      if (!_current(revision) || !identical(input, _photo)) return;
      if (recognized.trim().isEmpty) {
        throw const ScanFailure(ScanFailureKind.emptyText);
      }
      if (recognized.length > 20000) {
        throw const ScanFailure(ScanFailureKind.tooMuchText);
      }
      _text = recognized;
      _stage = ScanStage.ready;
    } catch (error) {
      if (_current(revision)) _fail(error, ScanFailureKind.recognition);
    } finally {
      final remaining = _inFlight[input]! - 1;
      if (remaining == 0) {
        _inFlight.remove(input);
        if (_retired.remove(input)) await _release(input);
      } else {
        _inFlight[input] = remaining;
      }
      if (_current(revision)) _notify();
    }
  }

  void editText(String value) {
    if (_disposed) return;
    ++_revision;
    _text = value;
    _message = null;
    _stage = _photo == null
        ? ScanStage.idle
        : (value.isEmpty ? ScanStage.preview : ScanStage.ready);
    _notify();
  }

  void cancel({String? message}) {
    if (_disposed) return;
    ++_revision;
    _message = message ?? 'İşlem iptal edildi.';
    _stage = _photo == null
        ? ScanStage.idle
        : (_text.isEmpty ? ScanStage.preview : ScanStage.ready);
    _notify();
  }

  void abandon() {
    if (_disposed) return;
    ++_revision;
    final previous = _photo;
    _photo = null;
    _text = '';
    _message = null;
    _stage = ScanStage.idle;
    if (previous != null) unawaited(_retire(previous));
    _notify();
  }

  Future<void> _retire(ScanPhoto photo) async {
    if (_inFlight.containsKey(photo)) {
      _retired.add(photo);
    } else {
      await _release(photo);
    }
  }

  Future<void> _release(ScanPhoto photo) async {
    try {
      await photos.release(photo);
    } catch (_) {
      if (!_disposed) {
        _message =
            'Geçici fotoğraf temizlenemedi. Uygulamayı yeniden açarak tekrar deneyebilirsin.';
        _notify();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_revision;
    onChanged = null;
    final previous = _photo;
    _photo = null;
    _text = '';
    _stage = ScanStage.idle;
    if (previous != null) unawaited(_retire(previous));
  }
}
