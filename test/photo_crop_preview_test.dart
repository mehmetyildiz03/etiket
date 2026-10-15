import 'dart:convert';
import 'dart:typed_data';
import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/photo_edit.dart';
import 'package:etiket/ui/photo_crop_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget editor(Uint8List photo) => MaterialApp(
    home: PhotoCropEditor(
      source: PhotoImageSource(
        width: 1200,
        height: 800,
        previewBytes: photo,
      ),
      initial: const PhotoEdit(),
      onApply: (_) async => null,
      onPaste: () {},
      onManual: () {},
    ),
  );

  testWidgets('crop dialog displays an actual decodable camera preview', (tester) async {
    final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
    ));
    await tester.pumpWidget(editor(png));
    await tester.pumpAndSettle();
    expect(find.text('Orijinal fotoğraf'), findsOneWidget);
    expect(find.byKey(const ValueKey('crop-canvas')), findsOneWidget);
    expect(find.textContaining('Orijinal fotoğraf gösterilemedi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed crop preview decode is never silently a blank image', (tester) async {
    await tester.pumpWidget(editor(Uint8List.fromList([0, 1, 2, 3])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Orijinal fotoğraf gösterilemedi'), findsOneWidget);
    expect(find.byKey(const ValueKey('crop-preview-error')), findsOneWidget);
    // The crop surface intentionally captures touch drags, so dragging the
    // scrollable's center would hit a crop handle rather than scroll. Jump the
    // scroll position to inspect the lazily built confirmation controls.
    final scrolling = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrolling.position.jumpTo(scrolling.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Kırpmayı uygula'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull,
      reason: 'cannot crop an original image that did not decode');
    expect(tester.takeException(), isNull);
  });
}
