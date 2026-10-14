import 'package:etiket/domain/composition_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import preview does not change the editable composition', () {
    final draft = CompositionDraft.sample();
    final oldId = draft.sections.first.id;
    final proposal = draft.prepareImport('100% wool');
    expect(proposal.label.isValid, isTrue);
    expect(draft.sections.first.id, oldId);
    expect(draft.sections.first.fibers.first.name, 'Pamuk');
  });

  test('a parsed composition requires explicit user verification', () {
    final draft = CompositionDraft.sample();
    expect(draft.applyImport(draft.prepareImport('100% wool')), isTrue);
    expect(draft.isValid, isTrue);
    expect(draft.canAnalyze, isFalse);
    expect(() => draft.verifiedGarment(), throwsStateError);
    draft.confirmSource(true);
    expect(draft.canAnalyze, isTrue);
    expect(draft.verifiedGarment().sections.single.fibers.single.name, 'Yün');
    draft.setPercentage(draft.sections.first.fibers.first.id, '90');
    expect(draft.sourceConfirmed, isFalse);
    expect(draft.canAnalyze, isFalse);
  });

  test('unknown names and missing ratios survive until manually corrected', () {
    final draft = CompositionDraft.sample();
    draft.applyImport(draft.prepareImport('70% CO\nmystery fiber'));
    final fiber = draft.sections.single.fibers.last;
    expect(fiber.name, isNull);
    expect(fiber.percentageText, isEmpty);
    expect(fiber.rawText, 'mystery fiber');
    draft.confirmSource(true);
    expect(draft.canAnalyze, isFalse);
    draft.setFiberName(fiber.id, 'Polyester');
    draft.setPercentage(fiber.id, '30');
    expect(draft.isValid, isTrue);
    expect(draft.sourceConfirmed, isFalse);
    draft.confirmSource(true);
    expect(draft.canAnalyze, isTrue);
    expect(draft.sections.single.fibers.last.rawText, 'mystery fiber');
  });

  test('edited or accepted compositions cannot be overwritten silently', () {
    final draft = CompositionDraft.sample();
    final id = draft.sections.first.fibers.first.id;
    draft.setPercentage(id, '80');
    final proposal = draft.prepareImport('100% wool');
    expect(draft.applyImport(proposal), isFalse);
    expect(draft.sections.first.fibers.first.percentageText, '80');
    expect(draft.applyImport(proposal, replaceUserChanges: true), isTrue);
    draft.confirmSource(true);
    expect(draft.applyImport(draft.prepareImport('100% cotton')), isFalse);
  });

  test('a stale proposal is rejected even with replacement permission', () {
    final draft = CompositionDraft.sample();
    final proposal = draft.prepareImport('100% wool');
    draft.setSectionName(draft.sections.first.id, 'Elle düzeltilmiş');
    expect(draft.applyImport(proposal, replaceUserChanges: true), isFalse);
    expect(draft.sections.first.name, 'Elle düzeltilmiş');
  });

  test('row identities and decimal ratios survive editing and deletion', () {
    final draft = CompositionDraft.sample();
    draft.applyImport(draft.prepareImport('Shell: 70,5% CO 29,5% PES\nLining: 100% VI'));
    final shell = draft.sections.first;
    final lining = draft.sections.last;
    final remaining = shell.fibers.last;
    draft.setSectionName(shell.id, 'Dış kumaş 1');
    draft.removeFiber(shell.fibers.first.id);
    expect(draft.sections.first.fibers.single.id, remaining.id);
    expect(draft.sections.first.fibers.single.percentageText, '29,5');
    draft.removeSection(shell.id);
    expect(draft.sections.single.id, lining.id);
    expect(draft.sections.single.name, 'Astar');
    expect(draft.sections.single.fibers.single.name, 'Viskon');
  });

  test('duplicate fibers in imported sections require explicit correction', () {
    final draft = CompositionDraft.sample();
    draft.applyImport(draft.prepareImport('50% cotton 50% CO'));
    expect(draft.isValid, isFalse);
    draft.setFiberName(draft.sections.single.fibers.last.id, 'Polyester');
    expect(draft.isValid, isTrue);
  });

  test('unrecognized headings remain blocked until manually reviewed', () {
    final draft = CompositionDraft.sample();
    draft.applyImport(draft.prepareImport('Pocket: 100% CO'));
    final section = draft.sections.single;
    expect(section.headingNeedsReview, isTrue);
    expect(draft.isValid, isFalse);
    draft.confirmSource(true);
    expect(draft.canAnalyze, isFalse);
    draft.setSectionName(section.id, 'Cep kumaşı');
    expect(draft.isValid, isTrue);
    expect(draft.sections.single.rawHeading, 'Pocket');
    draft.confirmSource(true);
    expect(draft.canAnalyze, isTrue);
  });

  test('zero-section proposals cannot erase a composition or its raw source', () {
    final draft = CompositionDraft.sample();
    draft.applyImport(draft.prepareImport('100% CO'));
    draft.confirmSource(true);
    final id = draft.sections.single.id;
    expect(draft.applyImport(draft.prepareImport(''), replaceUserChanges: true), isFalse);
    expect(draft.sections.single.id, id);
    expect(draft.rawText, '100% CO');
    expect(draft.canAnalyze, isTrue);
  });

  test('repeated deletion targets identity and cannot remove the surviving row', () {
    final draft = CompositionDraft.sample();
    final deleted = draft.sections.single.fibers.first.id;
    final survivor = draft.sections.single.fibers.last;
    draft.removeFiber(deleted);
    draft.removeFiber(deleted);
    expect(draft.sections.single.fibers.single.id, survivor.id);
    expect(draft.sections.single.fibers.single.name, 'Polyester');
    expect(draft.sections.single.fibers.single.percentageText, '30');
  });
}
