import 'photo_scan.dart';
import 'scan_services_stub.dart'
    if (dart.library.io) 'scan_services_native.dart'
    as platform;

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() => platform.createScanServices();
