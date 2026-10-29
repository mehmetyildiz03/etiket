import 'dart:async';
import 'dart:typed_data';
import 'photo_edit.dart';
import 'ocr_observation.dart';

enum PhotoSource { camera, gallery }

// Advisory only: derived from local image metrics, never OCR correctness.
enum PhotoCaptureHint {
  veryDark,
  veryBright,
  lowDetail;

  String get advice => switch (this) {
    PhotoCaptureHint.veryDark =>
      'Fotoğraf çok karanlık görünüyor. Daha aydınlıkta tekrar çekmeyi deneyebilirsin.',
    PhotoCaptureHint.veryBright =>
      'Fotoğraf çok parlak görünüyor. Işığı azaltıp tekrar çekmeyi deneyebilirsin.',
    PhotoCaptureHint.lowDetail =>
      'Fotoğrafta çok az ayrıntı görünüyor. Etiketi yakından ve net çekmeyi deneyebilirsin.',
  };
}

enum ScanStage {
  idle,
  recovering,
  picking,
  preview,
  recognizing,
  ready,
  transforming,
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
  modelLoad,
  invalidCrop,
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
    ScanFailureKind.modelLoad =>
      'OCR motoru veya dil modeli yüklenemedi. İlk kullanım için internet gerekir. Bağlantını kontrol edip tekrar dene; metin yapıştırma ve elle giriş de kullanılabilir.',
    ScanFailureKind.invalidCrop =>
      'Kırpma alanı geçersiz veya çok dar. Alanı fotoğrafın içinde, en az 32 piksel genişlik ve yükseklikte seç.',
  };
}

/// Only the source adapter owns the temporary file. The controller never deletes
/// a gallery original or sends an image/text to a server.
class ScanPhoto {
  ScanPhoto({
    required this.path,
    required Uint8List previewBytes,
    this.sourceImage,
    this.captureHint,
  }) : previewBytes = previewBytes.asUnmodifiableView();
  final String path;
  final Uint8List previewBytes;
  final PhotoImageSource? sourceImage;
  /// Optional guidance; never blocks recognition or validates percentages.
  final PhotoCaptureHint? captureHint;
}

class PhotoImageSource {
  PhotoImageSource({
    required this.width,
    required this.height,
    required Uint8List previewBytes,
    this.previewUrl,
  }) : previewBytes = previewBytes.asUnmodifiableView();
  final int width, height;
  final Uint8List previewBytes;
  /// Temporary local browser Blob URL, never transmitted to a server.
  final String? previewUrl;
}

abstract interface class PhotoEditingService {
  Future<ScanPhoto> editPhoto(ScanPhoto original, PhotoEdit edit);
}

abstract interface class CancelablePhotoEditingService {
  void cancelPhotoEditing();
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

abstract interface class DiagnosticTextRecognitionService {
  bool get supportsDiagnostics;
  Future<OcrObservation> recognizeObservation(ScanPhoto photo);
}

/// Optional browser capabilities; native and existing fake adapters stay simple.
abstract interface class ScanPresentation {
  bool get cameraAvailable;
  String get galleryLabel;
  String get preparationMessage;
}

abstract interface class ScanProgressSource {
  String? get progressMessage;
  set onProgress(void Function()? callback);
}

abstract interface class CancelableRecognition {
  void cancelRecognition();
}

abstract interface class DisposablePhotoSource {
  void cancelSelection();
  void disposePhotos();
}

class PhotoScanController {
  PhotoScanController(this.photos, this.recognizer) {
    if (recognizer case final ScanProgressSource progress) {
      progress.onProgress = () {
        if (_stage == ScanStage.recognizing) _notify();
      };
    }
  }
  final PhotoSourceService photos;
  final TextRecognitionService recognizer;
  void Function()? onChanged;
  ScanStage _stage = ScanStage.idle;
  ScanPhoto? _photo;
  ScanPhoto? _originalPhoto;
  PhotoEdit? _appliedEdit;
  bool _editingPhoto = false;
  String _text = '';
  OcrObservation? _observation;
  String? _message;
  int _revision = 0;
  bool _disposed = false;
  bool _pickerOpen = false;
  final Map<ScanPhoto, int> _inFlight = {};
  final Set<ScanPhoto> _retired = {};
  ScanStage get stage => _stage;
  ScanPhoto? get photo => _photo;
  ScanPhoto? get originalPhoto => _originalPhoto;
  PhotoEdit? get appliedEdit => _appliedEdit;
  bool get editingPhoto => _editingPhoto;
  bool get canEditPhoto =>
      !_disposed &&
      photos is PhotoEditingService &&
      _originalPhoto?.sourceImage != null &&
      !_pickerOpen;
  String get text => _text;
  OcrObservation? get observation => _observation;
  String? get message => _message;
  bool get canPick => !_disposed && photos.supported && !_pickerOpen;
  bool get busy => {
    ScanStage.picking,
    ScanStage.recovering,
    ScanStage.recognizing,
    ScanStage.transforming,
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

  /// A platform camera can hand off a real still without bypassing revision,
  /// cancellation, ownership, or explicit post-capture OCR review.
  Future<void> pickCustom(Future<ScanPhoto?> Function() select) =>
      _select(select, recovering: false);
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
    _observation = null;
    final revision = ++_revision;
    _stopRecognition();
    _stopEditing();
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
        final oldOriginal = _originalPhoto;
        _photo = selected;
        _originalPhoto = selected;
        _appliedEdit = null;
        _editingPhoto = false;
        _text = '';
        _stage = ScanStage.preview;
        if (previous != null && !identical(previous, selected)) {
          await _retire(previous);
        }
        if (oldOriginal != null &&
            !identical(oldOriginal, previous) &&
            !identical(oldOriginal, selected)) {
          await _retire(oldOriginal);
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
    if (input == null ||
        _pickerOpen ||
        _editingPhoto ||
        _stage == ScanStage.recognizing ||
        _stage == ScanStage.transforming) {
      return;
    }
    _observation = null;
    final revision = ++_revision;
    _stage = ScanStage.recognizing;
    _message = null;
    _inFlight[input] = (_inFlight[input] ?? 0) + 1;
    _notify();
    try {
      String recognized;
      if (recognizer case final DiagnosticTextRecognitionService diagnostics
          when diagnostics.supportsDiagnostics) {
        final observation = await diagnostics.recognizeObservation(input);
        if (!_current(revision) || !identical(input, _photo)) return;
        _observation = observation;
        if (observation.acceptedText == null) {
          _text = '';
          _stage = ScanStage.failed;
          _message = observation.explanation;
          return;
        }
        recognized = observation.acceptedText!;
      } else {
        recognized = await recognizer.recognize(input);
      }
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
    _observation = null;
    ++_revision;
    _stopRecognition();
    _stopEditing();
    _editingPhoto = false;
    _text = value;
    _message = null;
    _stage = _photo == null
        ? ScanStage.idle
        : (value.isEmpty ? ScanStage.preview : ScanStage.ready);
    _notify();
  }

  void cancel({String? message}) {
    if (_disposed) return;
    _observation = null;
    ++_revision;
    _stopRecognition();
    _stopEditing();
    if (photos case final DisposablePhotoSource source) {
      source.cancelSelection();
    }
    _editingPhoto = false;
    _message = message ?? 'İşlem iptal edildi.';
    _stage = _photo == null
        ? ScanStage.idle
        : (_text.isEmpty ? ScanStage.preview : ScanStage.ready);
    _notify();
  }

  void abandon() {
    if (_disposed) return;
    _observation = null;
    ++_revision;
    _stopRecognition();
    _stopEditing();
    if (photos case final DisposablePhotoSource source) {
      source.cancelSelection();
    }
    final previous = _photo;
    final original = _originalPhoto;
    _photo = null;
    _originalPhoto = null;
    _appliedEdit = null;
    _editingPhoto = false;
    _text = '';
    _message = null;
    _stage = ScanStage.idle;
    if (previous != null) unawaited(_retire(previous));
    if (original != null && !identical(original, previous)) {
      unawaited(_retire(original));
    }
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
    _observation = null;
    ++_revision;
    _stopRecognition();
    _stopEditing();
    if (recognizer case final ScanProgressSource progress) {
      progress.onProgress = null;
    }
    if (photos case final DisposablePhotoSource source) {
      source.disposePhotos();
    }
    onChanged = null;
    final previous = _photo;
    final original = _originalPhoto;
    _photo = null;
    _originalPhoto = null;
    _editingPhoto = false;
    _text = '';
    _stage = ScanStage.idle;
    if (previous != null) unawaited(_retire(previous));
    if (original != null && !identical(original, previous)) {
      unawaited(_retire(original));
    }
  }

  bool beginPhotoEdit() {
    if (!canEditPhoto || _stage == ScanStage.transforming) return false;
    _observation = null;
    ++_revision;
    _stopRecognition();
    _stopEditing();
    _editingPhoto = true;
    _stage = _text.isEmpty ? ScanStage.preview : ScanStage.ready;
    _message = null;
    _notify();
    return true;
  }

  void cancelPhotoEdit() {
    if (_disposed || !_editingPhoto) return;
    _observation = null;
    ++_revision;
    _stopEditing();
    _editingPhoto = false;
    _stage = _text.isEmpty ? ScanStage.preview : ScanStage.ready;
    _message = 'Fotoğraf düzenleme iptal edildi.';
    _notify();
  }

  Future<bool> applyPhotoEdit(PhotoEdit edit) async {
    final original = _originalPhoto;
    if (!canEditPhoto ||
        !_editingPhoto ||
        original == null ||
        _stage == ScanStage.transforming) {
      return false;
    }
    final source = original.sourceImage!;
    if (!edit.isValidFor(source.width, source.height)) {
      _message = const ScanFailure(ScanFailureKind.invalidCrop).message;
      _notify();
      return false;
    }
    _observation = null;
    final revision = ++_revision;
    _stopRecognition();
    _stopEditing();
    _stage = ScanStage.transforming;
    _message = null;
    _inFlight[original] = (_inFlight[original] ?? 0) + 1;
    _notify();
    try {
      final edited = await (photos as PhotoEditingService).editPhoto(
        original,
        edit,
      );
      if (!_current(revision) || !identical(original, _originalPhoto)) {
        await _retire(edited);
        return false;
      }
      final previous = _photo;
      _photo = edited;
      _appliedEdit = edit;
      _editingPhoto = false;
      _text = '';
      _stage = ScanStage.preview;
      if (previous != null &&
          !identical(previous, original) &&
          !identical(previous, edited)) {
        await _retire(previous);
      }
      return true;
    } catch (error) {
      if (_current(revision)) _fail(error, ScanFailureKind.invalidPhoto);
      return false;
    } finally {
      final remaining = _inFlight[original]! - 1;
      if (remaining == 0) {
        _inFlight.remove(original);
        if (_retired.remove(original)) await _release(original);
      } else {
        _inFlight[original] = remaining;
      }
      if (_current(revision)) _notify();
    }
  }

  void _stopEditing() {
    if (photos case final CancelablePhotoEditingService editable) {
      editable.cancelPhotoEditing();
    }
  }

  void _stopRecognition() {
    if (recognizer case final CancelableRecognition cancelable) {
      cancelable.cancelRecognition();
    }
  }
}
