'use strict';

// Benchmark-only scoring. Never changes the app's OCR proposal or fabric data.
function normalizeText(value) {
  if (typeof value !== 'string') throw new TypeError('Text must be a string');
  return value.normalize('NFC').replace(/\s+/gu, ' ').trim();
}

function levenshtein(source, target) {
  const a = Array.from(source), b = Array.from(target);
  if (a.length < b.length) return levenshtein(target, source);
  let previous = Array.from({length: b.length + 1}, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const next = [i];
    for (let j = 1; j <= b.length; j++) {
      next[j] = Math.min(previous[j] + 1, next[j - 1] + 1,
        previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    previous = next;
  }
  return previous[b.length];
}

function textDistance(reference, hypothesis) {
  const expected = normalizeText(reference), actual = normalizeText(hypothesis);
  const chars = [Array.from(expected), Array.from(actual)];
  const words = [expected ? expected.split(' ') : [], actual ? actual.split(' ') : []];
  return {
    characterEdits: levenshtein(chars[0], chars[1]),
    referenceCharacters: chars[0].length,
    wordEdits: levenshtein(words[0], words[1]),
    referenceWords: words[0].length
  };
}

function escaped(value) {
  return Array.from(value).map(c => '*+?.^$|(){}[]\\'.includes(c) ? '\\' + c : c).join('');
}

// Exact numerical ratio AND exact fiber token must occur within a narrow span.
// "8096 PAMUK" cannot count as a correct reading of "80% PAMUK".
// This scorer is separate from the production text acceptance filter.
function exactPairRatioOffsets(hypothesis, pair) {
  if (!pair || typeof pair.fiber !== 'string' ||
      typeof pair.percent !== 'string' || !/^(?:100|[1-9]?\d)(?:[.,]\d{1,2})?$/.test(pair.percent)) {
    throw new TypeError('Each expected pair requires fiber and numeric percent');
  }
  // Keep line boundaries to prefer same-line evidence over a nearby
  // fiber from another row when one printed percentage touches both.
  const text = hypothesis.normalize('NFC').replace(/\r\n?/gu, '\n')
    .replace(/[^\S\n\u2028\u2029]+/gu, ' ').trim().toLocaleUpperCase('tr-TR');
  const name = escaped(normalizeText(pair.fiber).toLocaleUpperCase('tr-TR'));
  const value = pair.percent.replace(/[.,]/g, '[.,]');
  // Horizontal whitespace is permitted; a line break cannot manufacture a ratio.
  const inlineSpace = '[\\p{Zs}\\t]*';
  const percentage = '(?:' + value + inlineSpace + '[%％]|[%％]' + inlineSpace + value + ')';
  // Capture the percentage itself so the same printed token cannot count
  // twice when a fiber name appears on both sides of it.
  const boundedRatio = '(?<![0-9A-Z])(' + percentage + ')(?![0-9])';
  const boundedName = '(?<![\\p{L}])' + name + '(?![\\p{L}])';
  const gap = '[\\s:;,.()\\/\\-]{0,18}';
  const offsets = new Map();
  for (const expression of [boundedRatio + gap + boundedName,
    boundedName + gap + boundedRatio]) {
    for (const match of text.matchAll(new RegExp(expression, 'gu'))) {
      const offset = match.index + match[0].indexOf(match[1]);
      const sameLine = !/[\n\u2028\u2029]/u.test(match[0]);
      offsets.set(offset, Boolean(offsets.get(offset)) || sameLine);
    }
  }
  return offsets;
}

function countExactPairOccurrences(hypothesis, pair) {
  return exactPairRatioOffsets(hypothesis, pair).size;
}

function containsExactPair(hypothesis, pair) {
  return countExactPairOccurrences(hypothesis, pair) > 0;
}

function scoreCase(fixture, output) {
  if (!fixture || !fixture.id || !['positive','negative'].includes(fixture.kind)) {
    throw new TypeError('A fixture must have id and positive/negative kind');
  }
  const text = output?.text ?? '', rawText = output?.rawText ?? text;
  if (typeof text !== 'string' || typeof rawText !== 'string') throw new TypeError('OCR text must be string');
  const accepted = output?.code == null && Boolean(normalizeText(text));
  const rawTranscription = typeof fixture.groundTruth === 'string' && normalizeText(fixture.groundTruth)
    ? textDistance(fixture.groundTruth, rawText) : null;
  const result = {id: fixture.id, kind: fixture.kind, accepted, rawTranscription,
    code: output?.code ?? null, elapsedMs: output?.elapsedMs ?? null};
  if (fixture.kind === 'negative') {
    result.falseAccepted = accepted;
    return result;
  }
  if (typeof fixture.groundTruth !== 'string' || !normalizeText(fixture.groundTruth) ||
      !Array.isArray(fixture.expectedPairs)) {
    throw new TypeError('Positive fixture requires checked groundTruth and expectedPairs');
  }
  // Rejected positive proposals get an empty hypothesis (CER=100%); raw engine
  // text also has its own CER, so reject-errors remain visible separately.
  const distance = textDistance(fixture.groundTruth, accepted ? text : '');
  const rawDistance = textDistance(fixture.groundTruth, rawText);
  // Repeated identical pairs across sections require repeated *printed*
  // occurrences. A single "80% PAMUK" must not satisfy two GT rows.
  const pairKey = pair => JSON.stringify([pair.percent.replace(',', '.'),
    normalizeText(pair.fiber).toLocaleUpperCase('tr-TR')]);
  const candidates = fixture.expectedPairs.map(pair =>
    accepted ? exactPairRatioOffsets(text, pair) : new Set());
  // A single printed percentage can touch two different fiber names.
  // If it matches distinct expected pairs, credit neither: ownership is unclear.
  const owners = new Map();
  candidates.forEach((offsets, index) => {
    const key = pairKey(fixture.expectedPairs[index]);
    for (const [offset, sameLine] of offsets) {
      const priority = sameLine ? 1 : 0;
      const previous = owners.get(offset);
      if (!previous || priority > previous.priority) {
        owners.set(offset, {priority, keys: new Set([key])});
      } else if (priority === previous.priority) {
        previous.keys.add(key);
      }
    }
  });
  const availableByKey = new Map();
  const usedPairs = new Map();
  const pairs = fixture.expectedPairs.map((pair, index) => {
    const key = pairKey(pair);
    if (!availableByKey.has(key)) {
      availableByKey.set(key, [...candidates[index]].filter(([offset, sameLine]) => {
        const owner = owners.get(offset);
        return owner.keys.size === 1 && owner.keys.has(key) &&
          owner.priority === (sameLine ? 1 : 0);
      }).length);
    }
    const used = (usedPairs.get(key) || 0) + 1;
    usedPairs.set(key, used);
    return {fiber: pair.fiber, percent: pair.percent,
      correct: accepted && used <= availableByKey.get(key)};
  });
  return {...result, falseRejected: !accepted, ...distance,
    rawCharacterEdits: rawDistance.characterEdits,
    rawWordEdits: rawDistance.wordEdits,
    referencePairs: pairs.length,
    correctPairs: pairs.filter(p => p.correct).length,
    fullyCorrectComposition: accepted && pairs.length > 0 && pairs.every(p => p.correct),
    pairs};
}

function summarize(results) {
  const positive = results.filter(v => v.kind === 'positive');
  const negative = results.filter(v => v.kind === 'negative');
  const sum = (arr, key) => arr.reduce((n, v) => n + (v[key] || 0), 0);
  const transcribed = results.filter(v => v.rawTranscription);
  const totalCharacters = sum(positive, 'referenceCharacters');
  const totalWords = sum(positive, 'referenceWords');
  const totalPairs = sum(positive, 'referencePairs');
  const rate = (a,b) => b ? a / b : null;
  const mean = xs => xs.length ? xs.reduce((a,b) => a+b,0)/xs.length : null;
  const q = (xs,p) => !xs.length ? null :
    [...xs].sort((a,b) => a-b)[Math.ceil(p*xs.length)-1];
  const ms = results.map(x => x.elapsedMs).filter(v => typeof v === 'number' && Number.isFinite(v));
  return {
    positiveCount: positive.length, negativeCount: negative.length,
    transcriptionCount: transcribed.length,
    transcriptionRawCer: rate(transcribed.reduce((n,v)=>n+v.rawTranscription.characterEdits,0),
      transcribed.reduce((n,v)=>n+v.rawTranscription.referenceCharacters,0)),
    transcriptionRawWer: rate(transcribed.reduce((n,v)=>n+v.rawTranscription.wordEdits,0),
      transcribed.reduce((n,v)=>n+v.rawTranscription.referenceWords,0)),
    cer: rate(sum(positive,'characterEdits'),totalCharacters),
    wer: rate(sum(positive,'wordEdits'),totalWords),
    rawCer: rate(sum(positive,'rawCharacterEdits'),totalCharacters),
    rawWer: rate(sum(positive,'rawWordEdits'),totalWords),
    pairExactRecall: rate(sum(positive,'correctPairs'),totalPairs),
    fullyCorrectCompositionRate: rate(positive.filter(v=>v.fullyCorrectComposition).length, positive.length),
    falseRejectRate: rate(positive.filter(v=>v.falseRejected).length,positive.length),
    falseAcceptRate: rate(negative.filter(v=>v.falseAccepted).length,negative.length),
    macroCer: mean(positive.map(x => x.characterEdits/x.referenceCharacters)),
    p50Ms: q(ms,.5), p95Ms: q(ms,.95)
  };
}

module.exports = {normalizeText, levenshtein, textDistance, containsExactPair, scoreCase, summarize};
