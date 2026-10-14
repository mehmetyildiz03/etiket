import 'fabric.dart';
import 'label_parser.dart';

class DraftFiber {
  final String id;
  final String? name;
  final String percentageText;
  final String? rawText;
  final List<LabelIssue> sourceIssues;
  const DraftFiber(this.id, this.name, this.percentageText,
      {this.rawText, this.sourceIssues = const []});

  num? get percent => parsePercentage(percentageText);
  bool get isValid => name != null && knownFibers.contains(name) && percent != null;
  DraftFiber withName(String? value) =>
      DraftFiber(id, value, percentageText, rawText: rawText, sourceIssues: sourceIssues);
  DraftFiber withPercentage(String value) =>
      DraftFiber(id, name, value, rawText: rawText, sourceIssues: sourceIssues);
}

class DraftSection {
  final String id;
  final String name;
  final List<DraftFiber> fibers;
  final String? rawHeading;
  final bool headingNeedsReview;
  final bool imported;
  DraftSection(this.id, this.name, Iterable<DraftFiber> fibers,
      {this.rawHeading, this.headingNeedsReview = false, this.imported = false})
      : fibers = List.unmodifiable(fibers);

  num get total => fibers.fold<num>(0, (sum, fiber) => sum + (fiber.percent ?? 0));
  bool get hasDuplicateFibers {
    final names = fibers.map((fiber) => fiber.name).whereType<String>().toList();
    return names.length != names.toSet().length;
  }
  bool get isValid => name.trim().isNotEmpty && !headingNeedsReview &&
      fibers.isNotEmpty && fibers.every((fiber) => fiber.isValid) &&
      (!imported || !hasDuplicateFibers) &&
      fibers.fold<int>(0, (sum, fiber) => sum + percentageUnits(fiber.percent!)!) == 10000;

  DraftSection withName(String value) => DraftSection(id, value, fibers,
      rawHeading: rawHeading, headingNeedsReview: false, imported: imported);
  DraftSection withFibers(Iterable<DraftFiber> values) => DraftSection(id, name, values,
      rawHeading: rawHeading, headingNeedsReview: headingNeedsReview, imported: imported);
}

/// A proposal is immutable and tied to the exact draft revision it was prepared against.
class LabelImportProposal {
  final ParsedLabel label;
  final int baseRevision;
  const LabelImportProposal(this.label, this.baseRevision);
}

/// Explicit updates keep stable IDs, revoke verification and reject stale imports.
/// Nothing here depends on Flutter, cameras or OCR.
class CompositionDraft {
  List<DraftSection> _sections = [];
  int _nextId = 0;
  int _revision = 0;
  bool _hasUserChanges = false;
  bool _sourceConfirmed = false;
  String? _rawText;

  CompositionDraft.sample() {
    _sections = [
      DraftSection(_id(), 'Ana kumaş', [
        DraftFiber(_id(), 'Pamuk', '70'),
        DraftFiber(_id(), 'Polyester', '30'),
      ]),
    ];
  }

  List<DraftSection> get sections => List.unmodifiable(_sections);
  String? get rawText => _rawText;
  bool get imported => _rawText != null;
  bool get sourceConfirmed => _sourceConfirmed;
  bool get hasUserChanges => _hasUserChanges;
  bool get isValid => _sections.isNotEmpty && _sections.every((section) => section.isValid);
  bool get canAnalyze => isValid && (!imported || _sourceConfirmed);

  String _id() => 'draft-${_nextId++}';
  void _touch() {
    _revision++;
    _hasUserChanges = true;
    _sourceConfirmed = false;
  }

  LabelImportProposal prepareImport(String text) =>
      LabelImportProposal(parseLabel(text), _revision);

  bool applyImport(LabelImportProposal proposal, {bool replaceUserChanges = false}) {
    if (proposal.baseRevision != _revision ||
        (_hasUserChanges && !replaceUserChanges) ||
        proposal.label.sections.isEmpty) {
      return false;
    }
    _sections = [
      for (final section in proposal.label.sections)
        DraftSection(_id(), section.name, [
          for (final fiber in section.fibers)
            DraftFiber(_id(), fiber.name,
              fiber.percent == null ? fiber.rawPercentage : formatPercentage(fiber.percent!),
              rawText: fiber.rawText, sourceIssues: fiber.issues),
        ],
          imported: true, rawHeading: section.rawHeading,
          headingNeedsReview: section.issues.any(
            (issue) => issue.code == LabelIssueCode.unknownSection,
          )),
    ];
    _rawText = proposal.label.rawText;
    _revision++;
    _sourceConfirmed = false;
    _hasUserChanges = false;
    return true;
  }

  void setSectionName(String id, String value) {
    _updateSection(id, (section) => section.withName(value));
  }
  void setFiberName(String id, String? value) {
    _updateFiber(id, (fiber) => fiber.withName(value));
  }
  void setPercentage(String id, String value) {
    _updateFiber(id, (fiber) => fiber.withPercentage(value));
  }
  void _updateSection(String id, DraftSection Function(DraftSection) update) {
    final index = _sections.indexWhere((section) => section.id == id);
    if (index == -1) {
      throw StateError('Unknown section');
    }
    _sections[index] = update(_sections[index]);
    _touch();
  }
  void _updateFiber(String id, DraftFiber Function(DraftFiber) update) {
    final index = _sections.indexWhere((section) => section.fibers.any((fiber) => fiber.id == id));
    if (index == -1) {
      throw StateError('Unknown fiber');
    }
    final section = _sections[index];
    _sections[index] = section.withFibers([
      for (final fiber in section.fibers) fiber.id == id ? update(fiber) : fiber,
    ]);
    _touch();
  }
  void addSection() {
    _sections.add(DraftSection(_id(), 'Yeni bölüm', [DraftFiber(_id(), 'Pamuk', '100')]));
    _touch();
  }
  void removeSection(String id) {
    if (_sections.length <= 1 || !_sections.any((section) => section.id == id)) {
      return;
    }
    _sections.removeWhere((section) => section.id == id);
    _touch();
  }
  void addFiber(String sectionId) {
    _updateSection(sectionId, (section) => section.withFibers([
      ...section.fibers, DraftFiber(_id(), 'Diğer', '0'),
    ]));
  }
  void removeFiber(String id) {
    final index = _sections.indexWhere((section) => section.fibers.any((fiber) => fiber.id == id));
    if (index == -1) {
      return; // A repeated tap must not delete a different surviving row.
    }
    final section = _sections[index];
    if (section.fibers.length <= 1) {
      return;
    }
    _updateSection(section.id, (value) => value.withFibers(
      value.fibers.where((fiber) => fiber.id != id),
    ));
  }
  void confirmSource(bool confirmed) {
    _sourceConfirmed = confirmed && isValid;
    _revision++;
    if (_sourceConfirmed) {
      _hasUserChanges = true;
    }
  }
  Garment verifiedGarment() {
    if (!canAnalyze) {
      throw StateError('Composition must be valid and reviewed before analysis');
    }
    return Garment('Kıyafet', [
      for (final section in _sections)
        FabricSection(section.name, [
          for (final fiber in section.fibers) FiberEntry(fiber.name!, fiber.percent!),
        ]),
    ]);
  }
}
