'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {normalizeText, levenshtein, textDistance, containsExactPair, scoreCase, summarize} =
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
