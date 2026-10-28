'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {normalizeText, levenshtein, textDistance, containsExactPair, scoreCase, summarize, compareAlternativeReading} =
  require('./ocr_benchmark_metrics.cjs');

test('NFC keeps Turkish dotted/dotless I, percentages and punctuation significant', () => {
  assert.equal(normalizeText('  I\u0307pek \n  %80  '), 'İpek %80');
  assert.equal(textDistance('İPEK %80', 'IPEK 8096').characterEdits > 0, true);
  assert.equal(levenshtein('PAMUK', 'PAMUK'), 0);
  assert.equal(levenshtein('PAMUK', 'PAMK'), 1);
});

test('CER and WER expose numeric substitutions; insertions may exceed 100%', () => {
  assert.deepEqual(textDistance('80% PAMUK', '8096 PAMUK'), {
    characterEdits: 2, referenceCharacters: 9, wordEdits: 1, referenceWords: 2
  });
  assert.equal(textDistance('a', 'abcdefgh').characterEdits, 7);
  assert.equal(textDistance('80% PAMUK', '').characterEdits, 9);
});

test('fiber and printed exact ratio must be adjacent, no inferred percent sign', () => {
  const p = {fiber: 'PAMUK', percent: '80'};
  assert.equal(containsExactPair('80% PAMUK', p), true);
  assert.equal(containsExactPair('PAMUK %80', p), true);
  assert.equal(containsExactPair('PAMUK 80%', p), true);
  assert.equal(containsExactPair('8096 PAMUK', p), false);
  assert.equal(containsExactPair('8O% PAMUK', p), false);
  assert.equal(containsExactPair('30% PAMUK', p), false);
  assert.equal(containsExactPair('180% PAMUK', p), false);
  assert.equal(containsExactPair('80% POLYESTER PAMUK', p), false);
  assert.equal(containsExactPair('2026 PAMUK', p), false);
  assert.equal(containsExactPair('CARE 40°C CO', {fiber:'CO', percent:'40'}), false);
});

test('Turkish spelling is strict: letters are not auto-corrected or de-accented', () => {
  assert.equal(containsExactPair('100% VİSKON', {fiber:'viskon',percent:'100'}), true);
  assert.equal(containsExactPair('100% VİSKON', {fiber:'viskón',percent:'100'}), false);
  assert.equal(containsExactPair('50,5% İPEK', {fiber:'ipek',percent:'50.5'}), true);
});

test('positive rejection gets empty accepted hypothesis, raw OCR is still measured', () => {
  const f = {id:'p1',kind:'positive',groundTruth:'80% PAMUK',expectedPairs:[{percent:'80',fiber:'PAMUK'}]};
  const r = scoreCase(f,{code:'emptyText',text:null,rawText:'8096 PAMUK'});
  assert.equal(r.accepted, false);
  assert.equal(r.falseRejected, true);
  assert.equal(r.characterEdits, 9);
  assert.equal(r.rawCharacterEdits, 2);
  assert.equal(r.correctPairs, 0);
  assert.equal(r.fullyCorrectComposition, false);
});

test('negatives are counted separately, no CER or WER on empty ground truth', () => {
  const accepted = scoreCase({id:'n1',kind:'negative'}, {code:null,text:'QOOC 2026'});
  const rejected = scoreCase({id:'n2',kind:'negative'}, {code:'emptyText',text:null,rawText:'noise'});
  assert.equal(accepted.falseAccepted,true);
  assert.equal(rejected.falseAccepted,false);
  const summary = summarize([accepted,rejected]);
  assert.equal(summary.falseAcceptRate,.5);
  assert.equal(summary.cer,null);
  assert.equal(summary.pairExactRecall,null);
});

test('structured fields and full composition are distinct from general text similarity', () => {
  const fixture={id:'label',kind:'positive',groundTruth:'80% PAMUK\n20% POLYESTER',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'}]};
  const right=scoreCase(fixture,{code:null,text:'80% PAMUK\n20% POLYESTER'});
  const wrong=scoreCase(fixture,{code:null,text:'80% PAMUK\n30% POLYESTER'});
  assert.equal(right.fullyCorrectComposition,true);
  assert.equal(wrong.correctPairs,1);
  assert.equal(wrong.fullyCorrectComposition,false);
  const totals=summarize([right,wrong,scoreCase({id:'n',kind:'negative'},{code:'emptyText',text:''})]);
  assert.equal(totals.pairExactRecall,.75);
  assert.equal(totals.fullyCorrectCompositionRate,.5);
  assert.equal(totals.falseRejectRate,0);
  assert.equal(totals.falseAcceptRate,0);
  assert.equal(totals.positiveCount,2);
  assert.equal(totals.negativeCount,1);
});

test('no real images means null rates, never a fabricated real accuracy percentage', () => {
  const empty=summarize([]);
  assert.deepEqual([empty.cer,empty.wer,empty.falseAcceptRate,empty.fullyCorrectCompositionRate],
    [null,null,null,null]);
  assert.throws(() => scoreCase({id:'r',kind:'positive',groundTruth:'',expectedPairs:[]},{code:null,text:'80% PAMUK'}));
});

test('readable non-label control has raw CER/WER without becoming an accepted fabric label', () => {
  const f={id:'control',kind:'negative',groundTruth:'PLEASE CLOSE THE DOOR'};
  const r=scoreCase(f,{text:null,code:'emptyText',rawText:'PLEASE CLOSE THE DOOR'});
  assert.equal(r.falseAccepted,false);
  assert.equal(r.rawTranscription.characterEdits,0);assert.equal(r.rawTranscription.wordEdits,0);
  const totals=summarize([r]);assert.equal(totals.transcriptionCount,1);
  assert.equal(totals.transcriptionRawCer,0);assert.equal(totals.transcriptionRawWer,0);
  assert.equal(totals.cer,null);assert.equal(totals.falseRejectRate,null);
});

test('control transcription mistakes are measured independently of filter rejection', () => {
  const r=scoreCase({id:'control',kind:'negative',groundTruth:'PLEASE CLOSE THE DOOR'},
    {text:null,code:'emptyText',rawText:'PLEASE CL0SE THE DOOR'});
  assert.equal(r.rawTranscription.characterEdits,1);assert.equal(r.rawTranscription.wordEdits,1);
  assert.equal(r.falseAccepted,false);
});

test('repeated expected fiber/percentage pairs need distinct printed occurrences', () => {
  const fixture = {id:'two-sections',kind:'positive',
    groundTruth:'DIŞ KUMAŞ\n80% PAMUK\nASTAR\n80% PAMUK',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'80',fiber:'PAMUK'}]};
  const once = scoreCase(fixture,{code:null,text:'DIŞ KUMAŞ\n80% PAMUK\nASTAR'});
  assert.equal(once.correctPairs,1);
  assert.equal(once.fullyCorrectComposition,false);
  // One printed percentage between two fiber names must not count twice.
  const shared = scoreCase(fixture,{code:null,text:'PAMUK 80% PAMUK'});
  assert.equal(shared.correctPairs,1);
  const twice = scoreCase(fixture,{code:null,text:'80% PAMUK\nPAMUK 80%'});
  assert.equal(twice.correctPairs,2);
  assert.equal(twice.fullyCorrectComposition,true);
  // This is multiplicity only; section placement remains unmeasured.
});

test('ambiguous shared ratio cannot credit two different expected fibers', () => {
  const fixture = {id:'two-fibers',kind:'positive',
    groundTruth:'80% PAMUK\n80% POLYESTER',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'80',fiber:'POLYESTER'}]};
  const ambiguous = scoreCase(fixture,{code:null,text:'PAMUK 80% POLYESTER'});
  assert.equal(ambiguous.correctPairs,0);
  assert.equal(ambiguous.fullyCorrectComposition,false);
  const reversed = scoreCase({...fixture,expectedPairs:[...fixture.expectedPairs].reverse()},
    {code:null,text:'PAMUK 80% POLYESTER'});
  assert.equal(reversed.correctPairs,0);
  const separate = scoreCase(fixture,{code:null,text:'80% PAMUK\n80% POLYESTER'});
  assert.equal(separate.correctPairs,2);
  assert.equal(separate.fullyCorrectComposition,true);
});


test('benchmark never joins a number and percent sign across a line boundary', () => {
  const pair = {fiber:'PAMUK',percent:'80'};
  for (const text of ['80\n% PAMUK', '%\n80 PAMUK',
    '80\r\n% PAMUK', '80\u2028% PAMUK', '%\u2029 80 PAMUK']) {
    assert.equal(containsExactPair(text, pair), false, text);
  }
  for (const text of ['80 % PAMUK', '80\t% PAMUK',
    '80\u2009% PAMUK', '%\u00a080 PAMUK']) {
    assert.equal(containsExactPair(text, pair), true, text);
  }
  const fixture = {id:'line-split-ratio',kind:'positive',
    groundTruth:'80% PAMUK',expectedPairs:[pair]};
  const result = scoreCase(fixture,{code:null,text:'80\n% PAMUK'});
  assert.equal(result.correctPairs,0);
  assert.equal(result.fullyCorrectComposition,false);
});


test('section-aware recall rejects swapped outer/lining pairs despite perfect global pair recall', () => {
  const fixture = {id:'sections',kind:'positive',
    groundTruth:'DIŞ KUMAŞ\n80% PAMUK\nASTAR\n100% VİSKON',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'100',fiber:'VİSKON'}],
    expectedSections:[
      {heading:'DIŞ KUMAŞ',expectedPairs:[{percent:'80',fiber:'PAMUK'}]},
      {heading:'ASTAR',expectedPairs:[{percent:'100',fiber:'VİSKON'}]}
    ]};
  const correct = scoreCase(fixture,{code:null,
    text:'DIŞ KUMAŞ\n80% PAMUK\nASTAR\n100% VİSKON'});
  assert.equal(correct.correctPairs,2);
  assert.equal(correct.sectionEvaluation.correctPairs,2);
  assert.equal(correct.sectionEvaluation.completeRecall,true);
  const swapped = scoreCase(fixture,{code:null,
    text:'DIŞ KUMAŞ\n100% VİSKON\nASTAR\n80% PAMUK'});
  assert.equal(swapped.correctPairs,2,'global pair recall alone misses the section error');
  assert.equal(swapped.sectionEvaluation.correctPairs,0);
  assert.equal(swapped.sectionEvaluation.completeRecall,false);
  const summary = summarize([correct,swapped]);
  assert.equal(summary.pairExactRecall,1);
  assert.equal(summary.sectionAnnotatedCount,2);
  assert.equal(summary.sectionPairExactRecall,.5);
  assert.equal(summary.sectionCompleteRecallRate,.5);
});

test('missing or repeated section headers never inherit another section pairs', () => {
  const fixture = {id:'sections',kind:'positive',
    groundTruth:'DIŞ KUMAŞ\n80% PAMUK\nASTAR\n100% VİSKON',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'100',fiber:'VİSKON'}],
    expectedSections:[
      {heading:'DIŞ KUMAŞ',expectedPairs:[{percent:'80',fiber:'PAMUK'}]},
      {heading:'ASTAR',expectedPairs:[{percent:'100',fiber:'VİSKON'}]}
    ]};
  const missing = scoreCase(fixture,{code:null,text:'80% PAMUK\nASTAR\n100% VİSKON'});
  assert.equal(missing.sectionEvaluation.correctPairs,1);
  assert.equal(missing.sectionEvaluation.completeRecall,false);
  const repeated = scoreCase(fixture,{code:null,
    text:'DIŞ KUMAŞ\n80% PAMUK\nDIŞ KUMAŞ\nASTAR\n100% VİSKON'});
  assert.equal(repeated.sectionEvaluation.correctPairs,1);
  assert.equal(repeated.sectionEvaluation.details[0].headerUnique,false);
  const rejected = scoreCase(fixture,{code:'emptyText',text:null,rawText:fixture.groundTruth});
  assert.equal(rejected.sectionEvaluation.correctPairs,0);
  assert.equal(rejected.sectionEvaluation.completeRecall,false);
  assert.equal(summarize([rejected]).sectionPairExactRecall,0);
});

test('section scoring is opt-in, and invalid section annotations fail closed', () => {
  const base={id:'unannotated',kind:'positive',groundTruth:'80% PAMUK',
    expectedPairs:[{percent:'80',fiber:'PAMUK'}]};
  const unannotated=scoreCase(base,{code:null,text:'80% PAMUK'});
  assert.equal(unannotated.sectionEvaluation,null);
  assert.equal(summarize([unannotated]).sectionPairExactRecall,null);
  assert.equal(summarize([unannotated]).sectionAnnotatedCount,0);
  assert.throws(() => scoreCase({...base,expectedSections:[
    {heading:'ASTAR',expectedPairs:[{percent:'100',fiber:'VİSKON'}]}
  ]},{code:null,text:'ASTAR\n100% VİSKON'}),/partition/);
  assert.throws(() => scoreCase({...base,expectedSections:[
    {heading:'ASTAR',expectedPairs:base.expectedPairs},
    {heading:'ASTAR',expectedPairs:base.expectedPairs}
  ]},{code:null,text:'ASTAR\n80% PAMUK'}),/unique/);
});

test('paired PSM diagnostics measure raw %/fiber recovery without auto-accepting PSM3', () => {
  const fixture={id:'psm',kind:'positive',groundTruth:'DIŞ KUMAŞ\n80% PAMUK',
    expectedPairs:[{percent:'80',fiber:'PAMUK'}],
    expectedSections:[{heading:'DIŞ KUMAŞ',expectedPairs:[{percent:'80',fiber:'PAMUK'}]}]};
  const first='DIŞ KUMAŞ\n8096 PAMUK';
  const second={mode:'autoPage',rawText:'DIŞ KUMAŞ\n80% PAMUK'};
  const comparison=compareAlternativeReading(fixture,first,second);
  assert.equal(comparison.firstPsm,6);
  assert.equal(comparison.secondPsm,3);
  assert.equal(comparison.firstExactPairs,0);
  assert.equal(comparison.secondExactPairs,1);
  assert.equal(comparison.firstSectionPairs,0);
  assert.equal(comparison.secondSectionPairs,1);
  assert.ok(comparison.firstRawCer>comparison.secondRawCer);
  assert.equal(comparison.secondRawCer,0);
  // This helper returns only evidence; the rejected production proposal
  // remains rejected and must never be replaced by the second OCR result.
  const rejected=scoreCase(fixture,{code:'emptyText',text:null,rawText:first});
  assert.equal(rejected.accepted,false);
  assert.equal(rejected.correctPairs,0);
});

test('paired OCR comparison does not invent missing PSM results or use negative controls', () => {
  const fixture={id:'psm',kind:'positive',groundTruth:'80% PAMUK',
    expectedPairs:[{percent:'80',fiber:'PAMUK'}]};
  assert.equal(compareAlternativeReading(fixture,'8096 PAMUK',null),null);
  assert.equal(compareAlternativeReading(fixture,'8096 PAMUK',
    {mode:'autoPage',rawText:''}),null);
  assert.equal(compareAlternativeReading(fixture,'8096 PAMUK',
    {mode:'unknown',rawText:'80% PAMUK'}),null);
  assert.equal(compareAlternativeReading({id:'negative',kind:'negative'},
    'noise',{mode:'sparseText',rawText:'80% PAMUK'}),null);
  const sparse=compareAlternativeReading(fixture,'80% PAMUK',
    {mode:'sparseText',rawText:'8096 PAMUK'});
  assert.equal(sparse.secondPsm,11);
  assert.equal(sparse.firstExactPairs,1);
  assert.equal(sparse.secondExactPairs,0);
  assert.equal(sparse.referenceSectionPairs,null);
});
