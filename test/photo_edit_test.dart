import 'dart:async';
import 'package:etiket/scan/photo_scan.dart';
import 'package:etiket/scan/photo_edit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'photo_scan_test.dart' show FakePhotos, FakeRecognizer;
import 'photo_flow_test.dart' show imagePhoto;

ScanPhoto editablePhoto(String id) {
  final bytes = imagePhoto(id).previewBytes;
  return ScanPhoto(
    path: id,
    previewBytes: bytes,
    sourceImage: PhotoImageSource(
      width: 1200,
      height: 800,
      previewBytes: bytes,
    ),
  );
}

class EditingPhotos extends FakePhotos implements PhotoEditingService {
  final edits = <({ScanPhoto source, PhotoEdit edit})>[];
  final pendingEdits = <Completer<ScanPhoto>>[];
  @override
  Future<ScanPhoto> editPhoto(ScanPhoto source, PhotoEdit edit) async {
    edits.add((source: source, edit: edit));
    return pendingEdits.isEmpty
        ? editablePhoto('crop-${edits.length}')
        : pendingEdits.removeAt(0).future;
  }
}

void main() {
  test(
    'quarter turns preserve the selected source region and four turns reset geometry',
    () {
      const original = PhotoEdit(left: .1, top: .2, width: .3, height: .4);
      final right = original.rotate(1);
      expect(right.quarterTurns, 1);
      expect(right.left, closeTo(.4, 1e-9));
      expect(right.top, .1);
      expect(right.width, .4);
      expect(right.height, .3);
      final back = right.rotate(-1);
      expect(back.left, closeTo(original.left, 1e-9));
      expect(back.top, closeTo(original.top, 1e-9));
      expect(back.width, original.width);
      expect(back.height, original.height);
      expect(original.rotate(4), original);
    },
  );
  test(
    'invalid, out-of-bounds, tiny and non-finite crops are rejected at original resolution',
    () {
      for (final edit in [
        const PhotoEdit(width: 0),
        const PhotoEdit(left: -.1),
        const PhotoEdit(left: .9, width: .3),
        const PhotoEdit(top: .9, height: .3),
        const PhotoEdit(width: .001),
        const PhotoEdit(height: double.nan),
        const PhotoEdit(left: double.infinity),
        const PhotoEdit(quarterTurns: 7),
      ]) {
        expect(edit.isValidFor(1200, 800), false, reason: '$edit');
      }
      expect(const PhotoEdit(left: .9, width: .1).isValidFor(1200, 800), true);
      expect(
        const PhotoEdit(quarterTurns: 1, width: .05).isValidFor(1200, 800),
        true,
      );
      expect(const PhotoEdit().isValidFor(0, 800), false);
    },
  );
  test(
    'rotation at the outer boundary stays inside the original without floating point gaps',
    () {
      for (var n = 0; n < 4; n++) {
        expect(
          const PhotoEdit(
            left: .9,
            top: .9,
            width: .1,
            height: .1,
          ).rotate(n).isValidFor(1200, 800),
          true,
        );
      }
    },
  );
  late EditingPhotos photos;
  late FakeRecognizer ocr;
  late PhotoScanController scan;
  setUp(() {
    photos = EditingPhotos()..next = editablePhoto('original');
    ocr = FakeRecognizer();
    scan = PhotoScanController(photos, ocr);
  });
  tearDown(() => scan.dispose());
  test(
    'crop invalidates OCR, always reuses original, and releases derivatives once',
    () async {
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      final original = scan.photo!;
      expect(scan.beginPhotoEdit(), true);
      expect(
        await scan.applyPhotoEdit(const PhotoEdit(left: .1, width: .8)),
        true,
      );
      final first = scan.photo!;
      expect(scan.stage, ScanStage.preview);
      expect(scan.text, isEmpty);
      expect(scan.originalPhoto, same(original));
      expect(photos.released, isEmpty);
      await scan.recognize();
      expect(ocr.calls.last, same(first));
      expect(scan.beginPhotoEdit(), true);
      await scan.applyPhotoEdit(const PhotoEdit(quarterTurns: 1));
      expect(photos.edits.last.source, same(original));
      expect(photos.released, [first]);
      final second = scan.photo!;
      scan.abandon();
      await Future<void>.delayed(Duration.zero);
      expect(photos.released.toSet(), {original, first, second});
      expect(photos.released.toSet().length, 3);
      expect(photos.released.length, 3);
    },
  );
  test(
    'cancel edit keeps last preview/OCR; invalid crop never invokes adapter',
    () async {
      await scan.pick(PhotoSource.gallery);
      await scan.recognize();
      final text = scan.text, photo = scan.photo;
      scan.beginPhotoEdit();
      expect(await scan.applyPhotoEdit(const PhotoEdit(width: 0)), false);
      expect(scan.message, contains('Kırpma'));
      expect(photos.edits, isEmpty);
      scan.cancelPhotoEdit();
      expect(scan.photo, same(photo));
      expect(scan.text, text);
      expect(scan.stage, ScanStage.ready);
    },
  );
  test('a late OCR cannot overwrite a newer crop or manual text', () async {
    await scan.pick(PhotoSource.gallery);
    final complete = Completer<String>();
    ocr.pending.add(complete);
    final reading = scan.recognize();
    scan.beginPhotoEdit();
    await scan.applyPhotoEdit(const PhotoEdit(width: .5));
    scan.editText('80% CO 20% PES');
    complete.complete('100% WO');
    await reading;
    expect(scan.text, '80% CO 20% PES');
    expect(scan.photo!.path, 'crop-1');
  });
  test(
    'cancel/reversed transforms/new photo cannot replace the latest image; temporary outputs retire',
    () async {
      await scan.pick(PhotoSource.gallery);
      final first = Completer<ScanPhoto>(), second = Completer<ScanPhoto>();
      photos.pendingEdits.addAll([first, second]);
      scan.beginPhotoEdit();
      final a = scan.applyPhotoEdit(const PhotoEdit(width: .5));
      scan.cancelPhotoEdit();
      scan.beginPhotoEdit();
      final b = scan.applyPhotoEdit(const PhotoEdit(height: .5));
      final latest = editablePhoto('latest');
      second.complete(latest);
      expect(await b, true);
      final stale = editablePhoto('stale');
      first.complete(stale);
      expect(await a, false);
      expect(scan.photo, same(latest));
      expect(photos.released, contains(stale));
      photos.next = editablePhoto('new-photo');
      await scan.pick(PhotoSource.gallery);
      expect(scan.photo, same(photos.next));
      expect(scan.appliedEdit, isNull);
    },
  );
  test(
    'dispose while crop is pending releases late output and original without notifications',
    () async {
      await scan.pick(PhotoSource.gallery);
      final original = scan.photo;
      final complete = Completer<ScanPhoto>();
      photos.pendingEdits.add(complete);
      scan.beginPhotoEdit();
      final editing = scan.applyPhotoEdit(const PhotoEdit());
      scan.dispose();
      final late = editablePhoto('late');
      complete.complete(late);
      await editing;
      expect(photos.released.toSet(), {original, late});
      expect(photos.released.length, 2);
    },
  );
}
