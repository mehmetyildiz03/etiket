import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'photo_scan.dart';
import 'web_scan_services.dart';

@JS('dokuOcr')
external _OcrBridge? get _bridge;

extension type _OcrBridge(JSObject _) implements JSObject {
  external bool get supported;
  external bool get cameraAvailable;
  external JSPromise<_PhotoResult> pickSafe(bool camera);
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
}

extension type _PickedPhoto(JSObject _) implements JSObject {
  external String get path;
  external JSUint8Array get bytes;
}

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() {
  final bridge = _JsBridge();
  return (
    photos: WebPhotoSource(bridge),
    recognizer: WebTextRecognizer(bridge),
  );
}

class _JsBridge implements BrowserScanBridge {
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
      return picked == null
          ? null
          : BrowserPhoto(picked.path, picked.bytes.toDart);
    } catch (error) {
      throw _error(error);
    }
  }

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
