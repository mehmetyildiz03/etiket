import 'photo_scan.dart';
import 'scan_services_stub.dart'
    if (dart.library.io) 'scan_services_native.dart'
    if (dart.library.js_interop) 'scan_services_web.dart'
    as platform;

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() => platform.createScanServices();
