import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_scan.dart';

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() =>
    (photos: NativePhotoSource(), recognizer: NativeTextRecognizer());

class NativePhotoSource implements PhotoSourceService {
  NativePhotoSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  final Map<ScanPhoto, Directory> _owned = {};
  static final Set<String> _activeDirectories = {};
  Future<void>? _initialization;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxPixels = 24000000;
  // D4.2: retain substantially more camera detail for tiny printed glyphs.
  // 4000x4000 <= maxPixels; the private adopt() boundary still rejects files
  // above 20 MiB / 24 MP before ML Kit. This is not an OCR accuracy claim.
  static const pickerMaxEdge = 4000.0;
  static const pickerJpegQuality = 95;
  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<void> _initialize() => _initialization ??= () async {
    // Only our private cache directories; never clear the system photo library.
    await for (final entry in Directory.systemTemp.list()) {
      if (entry is Directory &&
          !_activeDirectories.contains(entry.path) &&
          entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('doku-scan-')) {
        await entry.delete(recursive: true);
      }
    }
  }();

  @override
  Future<ScanPhoto?> pick(PhotoSource source) async {
    await _initialize();
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: pickerMaxEdge,
        maxHeight: pickerMaxEdge,
        imageQuality: pickerJpegQuality,
        requestFullMetadata: false,
      );
      return file == null ? null : await adopt(file);
    } on PlatformException catch (error) {
      throw mapPickerError(error);
    }
  }

  @override
  Future<ScanPhoto?> recover() async {
    if (!Platform.isAndroid) return null;
    await _initialize();
    final result = await _picker.retrieveLostData();
    if (result.exception != null) throw mapPickerError(result.exception!);
    if (result.isEmpty || result.files == null || result.files!.isEmpty) {
      return null;
    }
    // We request one image at a time. An unexpected multiple result is not guessed.
    if (result.files!.length != 1) {
      for (final file in result.files!) {
        await _removePickerCache(file);
      }
      throw const ScanFailure(ScanFailureKind.invalidPhoto);
    }
    return adopt(result.files!.single);
  }

  /// Public for verifying the file boundary with synthetic fixtures, without a camera.
  Future<ScanPhoto> adopt(XFile file) async {
    Directory? directory;
    try {
      final length = await file.length();
      if (length == 0) throw const ScanFailure(ScanFailureKind.invalidPhoto);
      if (length > maxBytes) throw const ScanFailure(ScanFailureKind.tooLarge);
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width * descriptor.height > maxPixels) {
          throw const ScanFailure(ScanFailureKind.tooLarge);
        }
        // Verify the actual encoded data, not just its header, at bounded size.
        final codec = await descriptor.instantiateCodec(targetWidth: 720);
        try {
          (await codec.getNextFrame()).image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
      directory = await Directory.systemTemp.createTemp('doku-scan-');
      _activeDirectories.add(directory.path);
      final copy = File('${directory.path}/label-image');
      await copy.writeAsBytes(bytes, flush: true);
      await _removePickerCache(file);
      final photo = ScanPhoto(path: copy.path, previewBytes: bytes);
      _owned[photo] = directory;
      return photo;
    } on ScanFailure {
      rethrow;
    } catch (_) {
      throw const ScanFailure(ScanFailureKind.invalidPhoto);
    } finally {
      if (directory == null || !_owned.values.contains(directory)) {
        try {
          if (directory != null) await directory.delete(recursive: true);
          if (directory != null) _activeDirectories.remove(directory.path);
        } finally {
          await _removePickerCache(file);
        }
      }
    }
  }

  Future<void> _removePickerCache(XFile file) async {
    final original = File(file.path);
    if (!await original.exists()) return;
    final cache = await Directory.systemTemp.resolveSymbolicLinks();
    final resolved = await original.resolveSymbolicLinks();
    if (resolved.startsWith('$cache${Platform.pathSeparator}')) {
      await original.delete();
    }
  }

  @override
  Future<void> release(ScanPhoto photo) async {
    final directory = _owned[photo];
    if (directory == null) return;
    if (await directory.exists()) await directory.delete(recursive: true);
    _owned.remove(photo);
    _activeDirectories.remove(directory.path);
  }
}

ScanFailure mapPickerError(PlatformException error) {
  return switch (error.code) {
    'camera_access_denied' ||
    'photo_access_denied' => const ScanFailure(ScanFailureKind.permission),
    'camera_access_denied_without_prompt' ||
    'photo_access_denied_without_prompt' ||
    'camera_access_restricted' ||
    'photo_access_restricted' => const ScanFailure(
      ScanFailureKind.permission,
      permanent: true,
    ),
    'no_available_camera' => const ScanFailure(
      ScanFailureKind.unavailableCamera,
    ),
    _ => const ScanFailure(ScanFailureKind.invalidPhoto),
  };
}

class NativeTextRecognizer implements TextRecognitionService {
  @override
  Future<String> recognize(ScanPhoto photo) async {
    // Android dependency bundles the Latin model: no runtime model download or
    // cloud recognition API. Each operation owns and closes its recognizer.
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      )).text;
    } catch (_) {
      throw const ScanFailure(ScanFailureKind.recognition);
    } finally {
      await recognizer.close();
    }
  }
}
