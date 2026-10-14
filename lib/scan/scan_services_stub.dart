import 'photo_scan.dart';

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() =>
    (photos: _UnsupportedPhotos(), recognizer: _UnsupportedRecognizer());

class _UnsupportedPhotos implements PhotoSourceService {
  @override
  bool get supported => false;
  @override
  Future<ScanPhoto?> pick(PhotoSource source) async =>
      throw const ScanFailure(ScanFailureKind.unsupported);
  @override
  Future<ScanPhoto?> recover() async => null;
  @override
  Future<void> release(ScanPhoto photo) async {}
}

class _UnsupportedRecognizer implements TextRecognitionService {
  @override
  Future<String> recognize(ScanPhoto photo) async =>
      throw const ScanFailure(ScanFailureKind.unsupported);
}
