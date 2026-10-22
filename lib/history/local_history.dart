import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/fabric.dart';

class SavedGarment {
  const SavedGarment(this.id, this.createdAt, this.title, this.source, this.garment);
  final String id;
  final DateTime createdAt;
  final String title;
  final String source;
  final Garment garment;

  Map<String, Object> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'title': title,
    'source': source,
    'sections': [for (final s in garment.sections) {
      'name': s.name,
      'fibers': [for (final f in s.fibers) {'name': f.name, 'percent': f.percent}],
    }],
  };

  factory SavedGarment.fromJson(Object? input) {
    if (input is! Map<String, dynamic> ||
        input.keys.any((k) => !{'id', 'createdAt', 'title', 'source', 'sections'}.contains(k))) {
      throw const FormatException('Unexpected history fields');
    }
    final id = input['id'], created = input['createdAt'],
        title = input['title'], source = input['source'], sections = input['sections'];
    if (id is! String || id.isEmpty || id.length > 90 ||
        created is! String || title is! String ||
        title.trim().isEmpty || title.length > 60 ||
        (source != 'manual' && source != 'label') ||
        sections is! List || sections.isEmpty || sections.length > 12) {
      throw const FormatException('Invalid history metadata');
    }
    final date = DateTime.tryParse(created);
    if (date == null || !date.isUtc) throw const FormatException('Invalid saved date');
    final parsed = <FabricSection>[];
    for (final s in sections) {
      if (s is! Map<String, dynamic> ||
          s.keys.any((k) => k != 'name' && k != 'fibers')) {
        throw const FormatException('Invalid history section');
      }
      final name = s['name'], fibers = s['fibers'];
      if (name is! String || name.trim().isEmpty || name.length > 80 ||
          fibers is! List || fibers.isEmpty || fibers.length > 30) {
        throw const FormatException('Invalid section contents');
      }
      final entries = <FiberEntry>[];
      for (final f in fibers) {
        if (f is! Map<String, dynamic> ||
            f.keys.any((k) => k != 'name' && k != 'percent')) {
          throw const FormatException('Invalid fiber');
        }
        final fiberName = f['name'], percent = f['percent'];
        if (fiberName is! String || !knownFibers.contains(fiberName) ||
            percent is! num || percentageUnits(percent) == null) {
          throw const FormatException('Invalid fiber ratio');
        }
        entries.add(FiberEntry(fiberName, percent));
      }
      parsed.add(FabricSection(name, List.unmodifiable(entries)));
    }
    final garment = Garment(title, List.unmodifiable(parsed));
    if (!garment.isValid) throw const FormatException('Invalid section sum');
    return SavedGarment(id, date, title, source, garment);
  }
}

abstract interface class HistoryStore {
  Future<String?> read();
  Future<void> write(String value);
}

class DeviceHistoryStore implements HistoryStore {
  DeviceHistoryStore([SharedPreferencesAsync? value]) : _prefs = value;
  static const storageKey = 'doku.local_compositions.v1';
  SharedPreferencesAsync? _prefs;
  // Lazy creation allows legacy widget tests without platform plugins to
  // inspect the rest of the app; missing storage still FAILS closed on read.
  SharedPreferencesAsync get _preferences => _prefs ??= SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(storageKey);
  @override
  Future<void> write(String value) => _preferences.setString(storageKey, value);
}

/// Serial writes in one session; malformed/future documents are never wiped.
class LocalHistoryRepository {
  LocalHistoryRepository(this.store);
  final HistoryStore store;
  static const maxEntries = 100;
  static const maxDocumentLength = 180000;
  Future<void> _queue = Future<void>.value();
  int _idSequence = 0;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<SavedGarment>> list() => _serialized(_load);

  Future<List<SavedGarment>> save({
    required Garment garment, required String title,
    required String source, required bool explicitlyReviewed,
  }) => _serialized(() async {
    if (!explicitlyReviewed || !garment.isValid || title.trim().isEmpty ||
        title.trim().length > 60 ||
        (source != 'manual' && source != 'label')) {
      throw StateError('Only explicitly reviewed valid results may be saved');
    }
    final current = await _load();
    if (current.length >= maxEntries) throw StateError('History is full');
    final stamp = DateTime.now().toUtc();
    final id = '${stamp.microsecondsSinceEpoch}-${_idSequence++}';
    final record = SavedGarment(id, stamp, title.trim(), source,
      Garment(title.trim(), List.unmodifiable([
        for (final s in garment.sections)
          FabricSection(s.name, List.unmodifiable([
            for (final f in s.fibers) FiberEntry(f.name, f.percent),
          ])),
      ])));
    final updated = [record, ...current];
    await _write(updated);
    return List.unmodifiable(updated);
  });

  Future<List<SavedGarment>> remove(String id) => _serialized(() async {
    final old = await _load();
    if (!old.any((x) => x.id == id)) throw StateError('Missing saved item');
    final updated = old.where((x) => x.id != id).toList();
    await _write(updated);
    return List.unmodifiable(updated);
  });

  Future<List<SavedGarment>> clearAll() => _serialized(() async {
    await _load(); // Refuse destructive operations on damaged storage.
    await _write([]);
    return const [];
  });

  Future<List<SavedGarment>> _load() async {
    final raw = await store.read();
    if (raw == null) return const [];
    // Empty persisted text is corrupt; never treat it as missing history.
    if (raw.isEmpty) throw const FormatException('Corrupted history — cannot overwrite');
    if (raw.length > maxDocumentLength) throw const FormatException('Oversized history');
    final Object? document;
    try { document = jsonDecode(raw); } on FormatException {
      throw const FormatException('Corrupted history — cannot overwrite');
    }
    if (document is! Map<String, dynamic> ||
        document.length != 2 || document['schemaVersion'] != 1 ||
        document['records'] is! List) {
      throw const FormatException('Unknown history format — cannot overwrite');
    }
    final records = document['records'] as List;
    if (records.length > maxEntries) throw const FormatException('History limit exceeded');
    final ids = <String>{};
    final result = <SavedGarment>[];
    for (final value in records) {
      final item = SavedGarment.fromJson(value);
      if (!ids.add(item.id)) throw const FormatException('Duplicate history identifier');
      result.add(item);
    }
    return List.unmodifiable(result);
  }

  Future<void> _write(List<SavedGarment> entries) async {
    final document = jsonEncode({'schemaVersion': 1,
      'records': [for (final entry in entries) entry.toJson()]});
    if (document.length > maxDocumentLength) throw StateError('Storage size limit');
    await store.write(document);
    if (await store.read() != document) throw StateError('History write not verified');
  }
}
