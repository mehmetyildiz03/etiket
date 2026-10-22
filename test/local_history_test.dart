import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:etiket/domain/fabric.dart';
import 'package:etiket/history/local_history.dart';

class FakeHistoryStore implements HistoryStore {
  String? data;
  bool denyWrites = false;
  bool silentWriteFailure = false;
  int reads = 0;
  @override
  Future<String?> read() async { reads++; return data; }
  @override
  Future<void> write(String value) async {
    if (denyWrites) throw StateError('Access denied/quota exceeded');
    if (silentWriteFailure) return;
    data = value;
  }
}

void main() {
  const garment = Garment('Örnek', [
    FabricSection('Dış kumaş', [
      FiberEntry('Polyester', 60), FiberEntry('Pamuk', 40),
    ]),
    FabricSection('Astar', [FiberEntry('Viskon', 100)]),
  ]);

  test('no history is not a fabricated demonstration record', () async {
    final repo = LocalHistoryRepository(FakeHistoryStore());
    expect(await repo.list(), isEmpty);
  });

  test('save requires explicit review, valid sums and a real label source', () async {
    final store = FakeHistoryStore(), repo = LocalHistoryRepository(store);
    await expectLater(repo.save(garment: garment,title:'Mont',source:'label',
      explicitlyReviewed:false),throwsStateError);
    await expectLater(repo.save(garment: garment,title:'Mont',source:'raw-ocr',
      explicitlyReviewed:true),throwsStateError);
    const wrong = Garment('x',[FabricSection('Dış kumaş',[
      FiberEntry('Pamuk',60), FiberEntry('Polyester',30)])]);
    await expectLater(repo.save(garment:wrong,title:'x',source:'manual',
      explicitlyReviewed:true),throwsStateError);
    expect(store.data, isNull);
  });

  test('verified multi-section ratios persist across repository restart', () async {
    final storage=FakeHistoryStore(), repository=LocalHistoryRepository(storage);
    final saved = await repository.save(
      garment:garment,title:'Ceket',source:'label',explicitlyReviewed:true);
    expect(saved,hasLength(1));
    final restarted = LocalHistoryRepository(storage);
    final back = await restarted.list();
    expect(back.single.title,'Ceket');
    expect(back.single.source,'label');
    expect(back.single.garment.sections,hasLength(2));
    expect(back.single.garment.sections[0].fibers[0].percent,60);
    expect(back.single.garment.sections[0].fibers[1].percent,40);
    expect(back.single.garment.sections[1].fibers.single.percent,100);
  });

  test('photo, exif, raw ocr, confidence and other fields never serialize', () async {
    final storage=FakeHistoryStore(), repository=LocalHistoryRepository(storage);
    await repository.save(garment:garment,title:'Mavi gömlek',source:'manual',
      explicitlyReviewed:true);
    final doc=jsonDecode(storage.data!) as Map<String,dynamic>;
    final entry=(doc['records'] as List).single as Map<String,dynamic>;
    expect(entry.keys.toSet(),{'id','createdAt','title','source','sections'});
    for (final prohibited in ['photo','exif','rawText','confidence','image','preview']) {
      expect(storage.data!.contains('"$prohibited"'),isFalse);
    }
  });

  test('two asynchronous saves are serialized instead of losing first entry', () async {
    final storage=FakeHistoryStore(), repository=LocalHistoryRepository(storage);
    final results=await Future.wait([
      repository.save(garment:garment,title:'Bir',source:'manual',explicitlyReviewed:true),
      repository.save(garment:garment,title:'İki',source:'manual',explicitlyReviewed:true),
    ]);
    expect(results[0],hasLength(1));
    expect(results[1],hasLength(2));
    expect((await repository.list()).map((x)=>x.title),containsAll(['Bir','İki']));
  });

  test('delete one and clear all update persisted state, with restarts', () async {
    final storage=FakeHistoryStore(), repository=LocalHistoryRepository(storage);
    final first=(await repository.save(garment:garment,title:'Bir',
      source:'manual',explicitlyReviewed:true)).single;
    await repository.save(garment:garment,title:'İki',
      source:'label',explicitlyReviewed:true);
    await repository.remove(first.id);
    expect((await LocalHistoryRepository(storage).list()).single.title,'İki');
    await repository.clearAll();
    expect(await LocalHistoryRepository(storage).list(),isEmpty);
  });

  test('corrupt and unknown versions are read-only; no silent wipe', () async {
    for (final raw in [
      '{not json', '{"schemaVersion":2,"records":[]}',
      '{"schemaVersion":1,"records":[{"unexpected":"field"}]}',
    ]) {
      final storage=FakeHistoryStore()..data=raw;
      final repository=LocalHistoryRepository(storage);
      await expectLater(repository.list(),throwsFormatException);
      await expectLater(repository.clearAll(),throwsFormatException);
      await expectLater(repository.save(garment:garment,title:'x',
        source:'manual',explicitlyReviewed:true),throwsFormatException);
      expect(storage.data,raw);
    }
  });

  test('write exception and silent denial are never reported as saved', () async {
    final storage=FakeHistoryStore()..denyWrites=true;
    final repository=LocalHistoryRepository(storage);
    await expectLater(repository.save(garment:garment,title:'Bir',
      source:'manual',explicitlyReviewed:true),throwsStateError);
    expect(storage.data,isNull);
    storage.denyWrites=false;
    storage.silentWriteFailure=true;
    await expectLater(repository.save(garment:garment,title:'İki',
      source:'manual',explicitlyReviewed:true),throwsStateError);
    expect(storage.data,isNull);
  });

  test('post-failure queue survives and subsequent valid save succeeds', () async {
    final storage=FakeHistoryStore()..denyWrites=true;
    final repository=LocalHistoryRepository(storage);
    await expectLater(repository.save(garment:garment,title:'İlk',
      source:'manual',explicitlyReviewed:true),throwsStateError);
    storage.denyWrites=false;
    expect(await repository.save(garment:garment,title:'Sonra',
      source:'manual',explicitlyReviewed:true),hasLength(1));
  });

  test('unknown extra metadata is rejected, not copied into saved document', () {
    final input={
      'id':'x','createdAt':'2026-10-22T10:00:00.000Z',
      'title':'x','source':'manual','sections':[
        {'name':'Dış kumaş','fibers':[{'name':'Pamuk','percent':100}]}
      ],
      'rawOcr':'Do not persist this'
    };
    expect(()=>SavedGarment.fromJson(input),throwsFormatException);
  });
}
