import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'photo_scan.dart';
import 'web_scan_services.dart';
import 'photo_edit.dart';
import 'ocr_observation.dart';

@JS('dokuOcr')
external _OcrBridge? get _bridge;

extension type _OcrBridge(JSObject _) implements JSObject {
  external bool get supported;
  external bool get cameraAvailable;
  external JSPromise<_PhotoResult> pickSafe(bool camera);
  external JSPromise<_PhotoResult> editSafe(String path, _EditOptions options);
  external void cancelEditing();
  external JSPromise<_TextResult> recognizeSafe(
    String path,
    JSFunction progress,
  );
  external void release(String path);
  external void cancelRecognition();
  external void cancelSelection();
  external void dispose();
}

extension type _PhotoResult(JSObject _) implements JSObject {
  external _PickedPhoto? get photo;
  external String? get code;
}

extension type _TextResult(JSObject _) implements JSObject {
  external String? get text;
  external String? get code;
  external _Observation? get observation;
}

extension type _Observation(JSObject _) implements JSObject {
  external String get rawText;
  external double? get confidence;
  external String get decision;
  external String? get acceptedText;
  external _SecondReading? get secondReading;
  external _SecondReading? get thirdReading;
}

extension type _SecondReading(JSObject _) implements JSObject {
  external String get rawText;
  external double? get confidence;
  external String get mode;
}

extension type _PickedPhoto(JSObject _) implements JSObject {
  external String get path;
  external JSUint8Array get bytes;
  external String? get captureHint;
  external JSUint8Array? get sourceBytes;
  external String? get sourcePreviewUrl;
  external int? get sourceWidth;
  external int? get sourceHeight;
}

extension type _EditOptions._(JSObject _) implements JSObject {
  external factory _EditOptions({
    double left,
    double top,
    double width,
    double height,
    int quarterTurns,
  });
}

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() {
  final bridge = _JsBridge();
  return (
    photos: WebPhotoSource(bridge),
    recognizer: WebTextRecognizer(bridge),
  );
}

class _JsBridge
    implements
        BrowserScanBridge,
        BrowserImageEditor,
        BrowserDiagnosticScanBridge {
  @override
  bool get supported => _bridge?.supported ?? false;
  @override
  bool get cameraAvailable =>
      web.window.isSecureContext && (_bridge?.cameraAvailable ?? false);
  @override
  Future<BrowserPhoto?> pick(bool camera) async {
    try {
      final result = await _bridge!.pickSafe(camera).toDart;
      if (result.code != null) throw BrowserScanException(result.code!);
      final picked = result.photo;
      return picked == null ? null : _photo(picked);
    } catch (error) {
      throw _error(error);
    }
  }

  BrowserPhoto _photo(_PickedPhoto picked) => BrowserPhoto(
    picked.path,
    Uint8List.fromList(picked.bytes.toDart),
    captureHint: switch (picked.captureHint) {
      'veryDark' => PhotoCaptureHint.veryDark,
      'veryBright' => PhotoCaptureHint.veryBright,
      'lowDetail' => PhotoCaptureHint.lowDetail,
      _ => null,
    },
    sourceImage: picked.sourceBytes == null
        ? null
        : PhotoImageSource(
            width: picked.sourceWidth!,
            height: picked.sourceHeight!,
            // Detach the preview from the JS ArrayBuffer lifetime; iOS
            // WebKit may reclaim/reuse the original Uint8Array after picking.
            previewBytes: Uint8List.fromList(picked.sourceBytes!.toDart),
            previewUrl: picked.sourcePreviewUrl,
          ),
  );

  @override
  Future<BrowserPhoto> editPhoto(String path, PhotoEdit edit) async {
    try {
      final result = await _bridge!
          .editSafe(
            path,
            _EditOptions(
              left: edit.left,
              top: edit.top,
              width: edit.width,
              height: edit.height,
              quarterTurns: edit.quarterTurns,
            ),
          )
          .toDart;
      if (result.code != null) throw BrowserScanException(result.code!);
      return _photo(result.photo!);
    } catch (error) {
      throw _error(error);
    }
  }

  @override
  void cancelEditing() => _bridge?.cancelEditing();

  @override
  Future<String> recognize(String path, void Function(String) progress) async {
    try {
      final result = await _bridge!
          .recognizeSafe(
            path,
            ((JSString message) => progress(message.toDart)).toJS,
          )
          .toDart;
      if (result.code != null) throw BrowserScanException(result.code!);
      return result.text!;
    } catch (error) {
      throw _error(error);
    }
  }

  @override
  Future<OcrObservation> recognizeObservation(
    String path,
    void Function(String) progress,
  ) async {
    try {
      final result = await _bridge!
          .recognizeSafe(
            path,
            ((JSString message) => progress(message.toDart)).toJS,
          )
          .toDart;
      final evidence = result.observation;
      if (evidence == null) {
        throw BrowserScanException(result.code ?? 'recognition');
      }
      final decision = switch (evidence.decision) {
        'noText' => OcrDecision.noText,
        'lowConfidence' => OcrDecision.lowConfidence,
        'noComposition' => OcrDecision.noComposition,
        'candidate' => OcrDecision.candidate,
        _ => throw const BrowserScanException('recognition'),
      };
      final second = evidence.secondReading;
      final third = evidence.thirdReading;
      // Both unverified alternatives are independent observations. PSM3 is
      // only relevant to a rejected primary; PSM11 may follow either a weak
      // accepted primary or a rejected PSM6. Neither changes acceptedText.
      if (second != null &&
          !(second.mode == 'sparseText' ||
              (decision != OcrDecision.candidate && second.mode == 'autoPage'))) {
        throw const BrowserScanException('recognition');
      }
      if (third != null &&
          (second == null ||
              decision == OcrDecision.candidate ||
              second.mode != 'autoPage' ||
              third.mode != 'sparseText')) {
        throw const BrowserScanException('recognition');
      }
      final observation = OcrObservation(
        rawText: evidence.rawText,
        confidence: evidence.confidence,
        decision: decision,
        secondReading: second == null ? null : OcrSecondReading(
          rawText: second.rawText,
          confidence: second.confidence,
          // JS mode and original decision were validated above. This only
          // identifies diagnostic evidence, never automatically accepts it.
          engine: OcrReadingEngine.tesseractJs,
          variant: second.mode == 'autoPage'
              ? OcrReadingVariant.automaticPagePsm3
              : OcrReadingVariant.sparseTextPsm11,
        ),
        thirdReading: third == null ? null : OcrSecondReading(
          rawText: third.rawText,
          confidence: third.confidence,
          engine: OcrReadingEngine.tesseractJs,
          variant: OcrReadingVariant.sparseTextPsm11,
        ),
      );
      if (observation.acceptedText != result.text ||
          observation.acceptedText != evidence.acceptedText ||
          result.code !=
              (decision == OcrDecision.candidate ? null : 'emptyText')) {
        throw const BrowserScanException('recognition');
      }
      return observation;
    } catch (error) {
      throw _error(error);
    }
  }

  BrowserScanException _error(Object error) {
    // JS returns typed safe codes; never inspect a JS exception using a Dart
    // runtime type check (not portable between dart2js and Dart Wasm).
    return error is BrowserScanException
        ? error
        : const BrowserScanException('recognition');
  }

  @override
  void release(String path) => _bridge?.release(path);
  @override
  void cancelRecognition() => _bridge?.cancelRecognition();
  @override
  void cancelSelection() => _bridge?.cancelSelection();
  @override
  void dispose() => _bridge?.dispose();
}
