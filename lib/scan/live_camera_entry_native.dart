import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'photo_scan.dart';
import 'scan_services_native.dart';
import 'native_live_camera_page.dart';

bool supported(PhotoSourceService photos) =>
    (Platform.isAndroid || Platform.isIOS) && photos is NativePhotoSource;

/// The native stream only advises. The actual XFile is adopted into the
/// existing private photo pipeline, then OCR/review is still explicit.
Future<ScanPhoto?> capture(BuildContext context, PhotoSourceService photos) async {
  if (!supported(photos)) return null;
  final file = await Navigator.of(context).push<XFile>(
    MaterialPageRoute(builder: (_) => const NativeLiveCameraPage()),
  );
  if (file == null) return null;
  return (photos as NativePhotoSource).adopt(file);
}
