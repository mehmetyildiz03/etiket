import 'dart:typed_data';

import 'package:etiket/scan/native_ocr_byte_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NV21 OCR reads sampled frame, not recycled camera bytes', () {
    final cameraBytes = Uint8List.fromList([
      10, 11, 12, 13, 14, 15, 16, 17, // 4x2 Y
      20, 21, 22, 23, // interleaved VU
    ]);
    final frozen = snapshotNativeOcrBytes(
      bytes: cameraBytes, width: 4, height: 2,
      rowStride: 4, bgra: false,
    );
    expect(frozen, isNotNull);
    expect(identical(frozen, cameraBytes), isFalse);
    cameraBytes.fillRange(0, cameraBytes.length, 250);
    expect(frozen, orderedEquals([
      10, 11, 12, 13, 14, 15, 16, 17, 20, 21, 22, 23,
    ]));
  });

  test('NV21 OCR drops trailing camera bytes instead of allocating them', () {
    final cameraBytes = Uint8List.fromList([
      10, 11, 12, 13, 14, 15, 16, 17,
      20, 21, 22, 23, 99, 99, 99, 99,
    ]);
    final frozen = snapshotNativeOcrBytes(
      bytes: cameraBytes, width: 4, height: 2,
      rowStride: 4, bgra: false,
    );
    expect(frozen, isNotNull);
    expect(frozen!.length, 12);
    expect(frozen, orderedEquals(cameraBytes.sublist(0, 12)));
  });

  test('iOS BGRA snapshot strips row padding and freezes visible pixels', () {
    final source = Uint8List.fromList([
      1, 2, 3, 4, 5, 6, 7, 8, 99, 99, 99, 99,
      11, 12, 13, 14, 15, 16, 17, 18,
    ]);
    final frozen = snapshotNativeOcrBytes(
      bytes: source, width: 2, height: 2,
      rowStride: 12, bgra: true,
    );
    expect(frozen, isNotNull);
    source.fillRange(0, source.length, 0);
    expect(frozen, orderedEquals([
      1, 2, 3, 4, 5, 6, 7, 8,
      11, 12, 13, 14, 15, 16, 17, 18,
    ]));
    expect(frozen!.length, 16); // 20 source bytes -> 16 visible bytes.
  });

  test('iOS tight BGRA also freezes bytes without adding padding', () {
    final source = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final frozen = snapshotNativeOcrBytes(
      bytes: source, width: 2, height: 2,
      rowStride: 8, bgra: true,
    );
    expect(frozen, orderedEquals(List<int>.generate(16, (i) => i)));
    source.fillRange(0, source.length, 255);
    expect(frozen!.first, 0);
    expect(frozen.last, 15);
  });

  test('truncated, padded NV21 and invalid dimensions fail closed', () {
    Uint8List? snap(int width, int height, int stride, int length,
        {bool bgra = false}) => snapshotNativeOcrBytes(
          bytes: Uint8List(length), width: width, height: height,
          rowStride: stride, bgra: bgra,
        );
    expect(snap(4, 2, 4, 11), isNull); // missing VU byte
    expect(snap(4, 2, 6, 20), isNull); // unsafe NV21 row padding
    expect(snap(3, 2, 3, 9), isNull); // odd NV21 geometry
    expect(snap(0, 2, 0, 0), isNull);
    expect(snap(2, 2, 7, 16, bgra: true), isNull);
    expect(snap(2, 2, 8, 15, bgra: true), isNull);
    expect(snap(2, 2, 12, 19, bgra: true), isNull);
    expect(snap(4000, 3001, 4000, 1), isNull); // >12 MP
    expect(snap(2, 2, 8, 16, bgra: true), isNotNull);
  });
}
