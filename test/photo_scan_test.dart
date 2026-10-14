import 'dart:async';
import 'dart:typed_data';

import 'package:etiket/scan/photo_scan.dart';
import 'package:flutter_test/flutter_test.dart';

ScanPhoto photo(String name) =>
    ScanPhoto(path: name, previewBytes: Uint8List(1));

class FakePhotos implements PhotoSourceService {
  @override
  bool supported = true;
  ScanPhoto? next;
  ScanPhoto? recovered;
  Object? error;
  Completer<ScanPhoto?>? pending;
  Completer<ScanPhoto?>? pendingRecovery;
  final List<PhotoSource> sources = [];
  final List<ScanPhoto> released = [];
  @override
  Future<ScanPhoto?> pick(PhotoSource source) async {
    sources.add(source);
    if (error != null) throw error!;
    return pending == null ? next : pending!.future;
  }

  @override
  Future<ScanPhoto?> recover() async =>
      pendingRecovery == null ? recovered : pendingRecovery!.future;
  @override
  Future<void> release(ScanPhoto photo) async {
    released.add(photo);
  }
}

class FakeRecognizer implements TextRecognitionService {
  String result = 'Shell: 70% CO 30% PES\nLining: 100% VI';
  Object? error;
  final List<ScanPhoto> calls = [];
  final List<Completer<String>> pending = [];
  @override
  Future<String> recognize(ScanPhoto photo) async {
    calls.add(photo);
    if (error != null) throw error!;
    return pending.isEmpty ? result : pending.removeAt(0).future;
  }
}

void main() {
  late FakePhotos photos;
  late FakeRecognizer ocr;
  late PhotoScanController scan;
  setUp(() {
    photos = FakePhotos();
    ocr = FakeRecognizer();
    scan = PhotoScanController(photos, ocr);
  });
  tearDown(() => scan.dispose());

  for (final source in PhotoSource.values) {
    test(
      '$source: selection previews without starting OCR or confirming data',
      () async {
        photos.next = photo('selected');
        await scan.pick(source);
        expect(photos.sources, [source]);
        expect(scan.stage, ScanStage.preview);
        expect(scan.photo, same(photos.next));
        expect(ocr.calls, isEmpty);
        await scan.recognize();
        expect(scan.stage, ScanStage.ready);
        expect(scan.text, ocr.result);
      },
    );
    test('$source: cancellation preserves the previous photo', () async {
      photos.next = photo('previous');
      await scan.pick(source);
      final previous = scan.photo;
      photos.next = null;
      await scan.pick(source);
      expect(scan.photo, same(previous));
      expect(scan.message, contains('iptal'));
      expect(ocr.calls, isEmpty);
    });
  }
  test(
    'temporary and permanent permission failures expose Turkish recovery',
    () async {
      for (final permanent in [false, true]) {
        photos.error = ScanFailure(
          ScanFailureKind.permission,
          permanent: permanent,
        );
        await scan.pick(PhotoSource.camera);
        expect(scan.stage, ScanStage.failed);
        expect(scan.message, contains(permanent ? 'ayarlarından' : 'izin'));
        expect(scan.photo, isNull);
      }
    },
  );
  test('empty, corrupt and oversized photos do not invoke OCR', () async {
    for (final kind in [
      ScanFailureKind.invalidPhoto,
      ScanFailureKind.tooLarge,
    ]) {
      photos.error = ScanFailure(kind);
      await scan.pick(PhotoSource.gallery);
      expect(scan.stage, ScanStage.failed);
      expect(ocr.calls, isEmpty);
    }
  });
  test(
    'empty or excessive text is rejected, OCR error can be retried',
    () async {
      photos.next = photo('a');
      await scan.pick(PhotoSource.camera);
      for (final value in [' \n ', 'x' * 20001]) {
        ocr.result = value;
        await scan.recognize();
        expect(scan.stage, ScanStage.failed);
        expect(scan.text, isEmpty);
      }
      ocr.error = StateError('native failure');
      await scan.recognize();
      expect(scan.message, contains('Etiket okunamadı'));
      ocr.error = null;
      ocr.result = '7O% CO\nmystery fiber';
      await scan.recognize();
      expect(scan.text, '7O% CO\nmystery fiber'); // Never silently repairs OCR.
    },
  );
  test('rapid duplicate picker and OCR requests run only once', () async {
    photos.pending = Completer();
    final picking = scan.pick(PhotoSource.camera);
    await scan.pick(PhotoSource.gallery);
    expect(photos.sources, [PhotoSource.camera]);
    photos.pending!.complete(photo('a'));
    await picking;
    final completion = Completer<String>();
    ocr.pending.add(completion);
    final recognizing = scan.recognize();
    await scan.recognize();
    expect(ocr.calls, hasLength(1));
    completion.complete('100% CO');
    await recognizing;
  });
  test('manual text correction wins over a late OCR result', () async {
    photos.next = photo('a');
    await scan.pick(PhotoSource.camera);
    final completion = Completer<String>();
    ocr.pending.add(completion);
    final pending = scan.recognize();
    scan.editText('80% CO 20% PES');
    completion.complete('100% WO');
    await pending;
    expect(scan.text, '80% CO 20% PES');
    expect(scan.busy, isFalse);
  });
  test('reversed OCR completions cannot replace the new photo/text', () async {
    final a = photo('a'), b = photo('b');
    photos.next = a;
    await scan.pick(PhotoSource.camera);
    final first = Completer<String>(), second = Completer<String>();
    ocr.pending.addAll([first, second]);
    final older = scan.recognize();
    photos.next = b;
    await scan.pick(PhotoSource.gallery);
    expect(
      photos.released,
      isNot(contains(a)),
    ); // Native OCR still uses its file.
    final newer = scan.recognize();
    second.complete('100% VI');
    await newer;
    first.complete('100% WO');
    await older;
    expect(scan.photo, same(b));
    expect(scan.text, '100% VI');
    expect(photos.released.where((p) => identical(p, a)), hasLength(1));
  });
  test(
    'cancel/background interruption ignores late results and permits retry',
    () async {
      photos.next = photo('a');
      await scan.pick(PhotoSource.camera);
      final completion = Completer<String>();
      ocr.pending.add(completion);
      final pending = scan.recognize();
      scan.cancel(message: 'Tarama duraklatıldı.');
      expect(scan.stage, ScanStage.preview);
      expect(scan.message, contains('duraklatıldı'));
      completion.complete('100% WO');
      await pending;
      expect(scan.text, isEmpty);
      await scan.recognize();
      expect(scan.stage, ScanStage.ready);
    },
  );
  test(
    'leaving screen/disposal cleans late picks and OCR without notification',
    () async {
      photos.pending = Completer();
      final selecting = scan.pick(PhotoSource.gallery);
      final a = photo('late');
      scan.abandon();
      photos.pending!.complete(a);
      await selecting;
      expect(scan.photo, isNull);
      expect(photos.released, contains(a));
      photos.pending = null;
      photos.next = photo('ocr');
      await scan.pick(PhotoSource.camera);
      final completion = Completer<String>();
      ocr.pending.add(completion);
      final pending = scan.recognize();
      var notifications = 0;
      scan.onChanged = () => notifications++;
      scan.dispose();
      final count = notifications;
      completion.complete('100% WO');
      await pending;
      expect(notifications, count);
      expect(photos.released, contains(photos.next));
    },
  );
  test(
    'lost Android picker result is previewed, but cannot displace a new session',
    () async {
      photos.recovered = photo('recovered');
      await scan.recover();
      expect(scan.stage, ScanStage.preview);
      expect(ocr.calls, isEmpty);
      scan.abandon();
      photos.pendingRecovery = Completer();
      final recovering = scan.recover();
      scan.abandon();
      final late = photo('old');
      photos.pendingRecovery!.complete(late);
      await recovering;
      expect(scan.photo, isNull);
      expect(photos.released, contains(late));
    },
  );
  test(
    'overlapping retries keep the shared photo until both recognizers finish',
    () async {
      final input = photo('shared');
      photos.next = input;
      await scan.pick(PhotoSource.camera);
      final first = Completer<String>(), second = Completer<String>();
      ocr.pending.addAll([first, second]);
      final oldRead = scan.recognize();
      scan.cancel();
      final newRead = scan.recognize();
      second.complete('100% CO');
      await newRead;
      scan.abandon();
      expect(photos.released, isEmpty);
      first.complete('100% WO');
      await oldRead;
      expect(scan.text, isEmpty);
      expect(photos.released, [input]);
    },
  );
  test('unsupported platforms never invoke native picker/OCR', () async {
    photos.supported = false;
    await scan.pick(PhotoSource.camera);
    await scan.recognize();
    expect(photos.sources, isEmpty);
    expect(ocr.calls, isEmpty);
    expect(scan.message, contains('desteklenmiyor'));
  });
}
