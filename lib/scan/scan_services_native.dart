import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_scan.dart';
import 'photo_edit.dart';
import 'native_crop_pixels.dart';
import 'native_capture_guidance.dart';

({PhotoSourceService photos, TextRecognitionService recognizer})
createScanServices() =>
    (photos: NativePhotoSource(), recognizer: NativeTextRecognizer());

class NativePhotoSource
    implements PhotoSourceService, PhotoEditingService, CancelablePhotoEditingService {
  NativePhotoSource({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  final Map<ScanPhoto, Directory> _owned = {};
  static final Set<String> _activeDirectories = {};
  Future<void>? _initialization;
  int _editRevision = 0;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxPixels = 24000000;
  // D4.2: retain substantially more camera detail for tiny printed glyphs.
  // 4000x4000 <= maxPixels; the private adopt() boundary still rejects files
  // above 20 MiB / 24 MP before ML Kit. This is not an OCR accuracy claim.
  static const pickerMaxEdge = 4000.0;
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
        // Do not request additional lossy JPEG recompression of small glyphs.
        // The picker may still re-encode when a source exceeds 4000px.
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
      PhotoCaptureHint? captureHint;
      PhotoImageSource? sourceImage;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width <= 0 || descriptor.height <= 0) {
          throw const ScanFailure(ScanFailureKind.invalidPhoto);
        }
        if (descriptor.width * descriptor.height > maxPixels) {
          throw const ScanFailure(ScanFailureKind.tooLarge);
        }
        // Bound the LONG edge, not just the width: a 100x4000 portrait
        // must not be upscaled into a huge validation decode.
        final landscape = descriptor.width >= descriptor.height;
        final codec = await descriptor.instantiateCodec(
          targetWidth: landscape
              ? (descriptor.width > 720 ? 720 : descriptor.width)
              : null,
          targetHeight: landscape
              ? null
              : (descriptor.height > 720 ? 720 : descriptor.height),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            // The native crop editor previews the decoder's EXIF-oriented
            // pixels, not a separately interpreted JPEG thumbnail.
            try {
              final preview = await frame.image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (preview != null) {
                final swap = (descriptor.width > descriptor.height &&
                        frame.image.width < frame.image.height) ||
                    (descriptor.width < descriptor.height &&
                        frame.image.width > frame.image.height);
                sourceImage = PhotoImageSource(
                  width: swap ? descriptor.height : descriptor.width,
                  height: swap ? descriptor.width : descriptor.height,
                  previewBytes: Uint8List.fromList(preview.buffer.asUint8List(
                    preview.offsetInBytes, preview.lengthInBytes,
                  )),
                );
              }
            } catch (_) {
              // Cropping is optional; never block the original ML Kit input.
            }
            // Hints are best-effort and cannot prevent OCR or change pixels.
            // The original encoded bytes still go to private ML Kit input.
            try {
              final rgba = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              if (rgba != null) {
                captureHint = nativeCaptureHintFromRgba(
                  rgba.buffer.asUint8List(
                    rgba.offsetInBytes,
                    rgba.lengthInBytes,
                  ),
                  frame.image.width,
                  frame.image.height,
                );
              }
            } catch (_) {
              // Some platform decoders cannot export RGBA; omit the hint.
            }
          } finally {
            frame.image.dispose();
          }
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
      final photo = ScanPhoto(
        path: copy.path,
        previewBytes: bytes,
        captureHint: captureHint,
        sourceImage: sourceImage,
      );
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

  @override
  void cancelPhotoEditing() => ++_editRevision;

  @override
  Future<ScanPhoto> editPhoto(ScanPhoto original, PhotoEdit edit) async {
    final source = original.sourceImage;
    if (source == null || !_owned.containsKey(original) ||
        !edit.isValidFor(source.width, source.height)) {
      throw const ScanFailure(ScanFailureKind.invalidCrop);
    }
    final revision = _editRevision;
    Directory? directory;
    try {
      final pixels = await renderNativeCrop(original.previewBytes, source, edit);
      if (revision != _editRevision || !_owned.containsKey(original)) {
        throw const ScanFailure(ScanFailureKind.invalidCrop);
      }
      directory = await Directory.systemTemp.createTemp('doku-scan-');
      _activeDirectories.add(directory.path);
      final copy = File('${directory.path}/label-crop.png');
      await copy.writeAsBytes(pixels, flush: true);
      if (revision != _editRevision || !_owned.containsKey(original)) {
        throw const ScanFailure(ScanFailureKind.invalidCrop);
      }
      final photo = ScanPhoto(
        path: copy.path,
        previewBytes: pixels,
        sourceImage: source,
      );
      _owned[photo] = directory;
      return photo;
    } on ScanFailure {
      rethrow;
    } catch (_) {
      throw const ScanFailure(ScanFailureKind.invalidPhoto);
    } finally {
      if (directory != null && !_owned.values.contains(directory)) {
        try {
          await directory.delete(recursive: true);
        } finally {
          _activeDirectories.remove(directory.path);
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
