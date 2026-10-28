import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'photo_edit.dart';
import 'photo_scan.dart';

/// Decode the SAME private original used for the native crop preview, and
/// render exactly the user-selected region into a local PNG for ML Kit.
/// No OCR guesses, network requests, EXIF copies or persisted diagnostics.
Future<Uint8List> renderNativeCrop(
  Uint8List encoded,
  PhotoImageSource source,
  PhotoEdit edit,
) async {
  if (!edit.isValidFor(source.width, source.height)) {
    throw const ScanFailure(ScanFailureKind.invalidCrop);
  }
  const maxPixels = 24000000;
  const maxBytes = 20 * 1024 * 1024;
  final rotatedWidth =
      edit.quarterTurns.isEven ? source.width : source.height;
  final rotatedHeight =
      edit.quarterTurns.isEven ? source.height : source.width;
  // Snap BOTH crop edges to decoded source pixels. Rounding only the size
  // leaves a fractional source rectangle and resamples tiny printed glyphs.
  // The same integer rectangle is used for every 0/90/180/270 degree turn.
  final leftPixel = (edit.left * rotatedWidth).round().clamp(0, rotatedWidth).toInt();
  final topPixel = (edit.top * rotatedHeight).round().clamp(0, rotatedHeight).toInt();
  final rightPixel =
      ((edit.left + edit.width) * rotatedWidth)
          .round()
          .clamp(0, rotatedWidth)
          .toInt();
  final bottomPixel =
      ((edit.top + edit.height) * rotatedHeight)
          .round()
          .clamp(0, rotatedHeight)
          .toInt();
  final targetWidth = rightPixel - leftPixel;
  final targetHeight = bottomPixel - topPixel;
  if (targetWidth < 32 ||
      targetHeight < 32 ||
      targetWidth * targetHeight > maxPixels) {
    throw const ScanFailure(ScanFailureKind.invalidCrop);
  }

  final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  ui.Picture? picture;
  ui.Image? cropped;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > maxPixels) {
      throw const ScanFailure(ScanFailureKind.tooLarge);
    }
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    // If a platform decoder handles EXIF differently between the bounded
    // preview and the full image, fail rather than OCR the wrong crop pixels.
    if (image.width != source.width || image.height != source.height) {
      throw const ScanFailure(ScanFailureKind.invalidCrop);
    }

    final left = leftPixel.toDouble();
    final top = topPixel.toDouble();
    final width = targetWidth.toDouble();
    final height = targetHeight.toDouble();
    final sourceRect = switch (edit.quarterTurns) {
      0 => ui.Rect.fromLTWH(left, top, width, height),
      1 => ui.Rect.fromLTWH(top, image.height - left - width, height, width),
      2 => ui.Rect.fromLTWH(
          image.width - left - width,
          image.height - top - height,
          width,
          height,
        ),
      3 => ui.Rect.fromLTWH(image.width - top - height, left, height, width),
      _ => throw const ScanFailure(ScanFailureKind.invalidCrop),
    };
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    switch (edit.quarterTurns) {
      case 0:
        break;
      case 1:
        canvas.translate(targetWidth.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(targetWidth.toDouble(), targetHeight.toDouble());
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, targetHeight.toDouble());
        canvas.rotate(-math.pi / 2);
        break;
      default:
        throw const ScanFailure(ScanFailureKind.invalidCrop);
    }
    canvas.drawImageRect(
      image,
      sourceRect,
      ui.Rect.fromLTWH(
        0,
        0,
        (edit.quarterTurns.isEven ? targetWidth : targetHeight).toDouble(),
        (edit.quarterTurns.isEven ? targetHeight : targetWidth).toDouble(),
      ),
      // No bilinear filtering: a 1:1 pixel-aligned crop should preserve
      // thin strokes and percent signs rather than blend adjacent pixels.
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    picture = recorder.endRecording();
    cropped = await picture.toImage(targetWidth, targetHeight);
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const ScanFailure(ScanFailureKind.invalidPhoto);
    if (png.lengthInBytes > maxBytes) {
      throw const ScanFailure(ScanFailureKind.tooLarge);
    }
    return Uint8List.fromList(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    cropped?.dispose();
    picture?.dispose();
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
