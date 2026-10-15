'use strict';
/*
 * Browser-backed OCR BENCHMARK. Not a production feature or fake OCR adapter.
 * --synthetic: CI-safe generated examples, NEVER interpreted as real-photo accuracy.
 * --manifest ./PRIVATE.json --out /outside-repo/report: licensed/consented
 *    manually transcribed local photos, never committed or uploaded to CI.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {chromium} = require('../tool/web_ocr/node_modules/playwright');
const {scoreCase, summarize} = require('./ocr_benchmark_metrics.cjs');

const baseUrl = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
const index = process.argv.indexOf('--manifest');
const synthetic = index < 0;
const manifestPath = synthetic ? null : path.resolve(process.argv[index + 1] || '');
const outIndex = process.argv.indexOf('--out');
if (!synthetic && outIndex < 0) throw new Error('Private run requires --out OUTSIDE-REPO-DIRECTORY');
const dest = outIndex >= 0
  ? path.resolve(process.argv[outIndex + 1])
  : path.resolve('build/web-ocr-evidence/benchmark-synthetic');
if (!synthetic && (dest === process.cwd() || dest.startsWith(process.cwd() + path.sep))) {
  throw new Error('Private OCR/GT report must stay outside repo build/artifact directories');
}
fs.mkdirSync(dest, {recursive:true});

const syntheticFixtures = [
  {id:'clean-tr',kind:'positive',group:'clear',generator:'clean',
    groundTruth:'80% PAMUK\n20% POLYESTER',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'}]},
  {id:'sections-tr',kind:'positive',group:'multi-section',generator:'sections',
    groundTruth:'DIŞ KUMAŞ\n80% PAMUK\n20% POLYESTER\nASTAR\n100% VİSKON',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'},
      {percent:'100',fiber:'VİSKON'}]},
  {id:'skew-small',kind:'positive',group:'small-skew',generator:'skew',
    groundTruth:'80% PAMUK\n20% POLYESTER',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'}]},
  {id:'dark-faint',kind:'positive',group:'low-contrast',generator:'dark',
    groundTruth:'80% PAMUK\n20% POLYESTER',
    expectedPairs:[{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'}]},
  {id:'blank',kind:'negative',group:'no-text',generator:'blank'},
  {id:'weave',kind:'negative',group:'fabric-no-text',generator:'woven'},
  {id:'unrelated-year',kind:'negative',group:'non-composition',generator:'year',
    groundTruth:'2026 COTTON'},
  {id:'clear-writing-en',kind:'negative',group:'readable-non-label',generator:'writing-en',
    groundTruth:'PLEASE CLOSE THE DOOR'},
  {id:'clear-writing-tr',kind:'negative',group:'readable-non-label',generator:'writing-tr',
    groundTruth:'BUGÜN HAVA GÜZEL'}
];

function getFixtures() {
  if (synthetic) return syntheticFixtures;
  const data = JSON.parse(fs.readFileSync(manifestPath,'utf8'));
  assert.equal(data.schemaVersion, 1);
  assert.ok(Array.isArray(data.cases) && data.cases.length > 0);
  const ids = new Set();
  for (const f of data.cases) {
    assert.ok(f.id && !ids.has(f.id) && /^[a-zA-Z0-9_-]{1,70}$/.test(f.id));
    ids.add(f.id);
    assert.ok(['positive','negative'].includes(f.kind));
    assert.ok(['dev','holdout'].includes(f.split), 'Real images must have dev/holdout');
    assert.equal(f.reviewedByHuman,true,'Transcriptions must be reviewed by a person');
    assert.equal(f.usageConsent,true,'Real images require permission');
    assert.ok(f.imagePath && /^[0-9a-f]{64}$/i.test(f.sha256));
    if (f.kind === 'positive') {
      assert.ok(f.groundTruth && Array.isArray(f.expectedPairs));
    }
  }
  return data.cases;
}

async function makeSynthetic(page, kind) {
  const base64 = await page.evaluate((kind) => {
    const c=document.createElement('canvas');
    c.width = 1100; c.height = 850;
    const g=c.getContext('2d');
    const dark=kind==='dark', woven=kind==='woven';
    g.fillStyle=dark?'#686660':woven?'#929589':'#ebe9e0';
    g.fillRect(0,0,1100,850);
    if(woven || kind==='skew') {
      for(let y=0;y<850;y+=7) {
        g.strokeStyle=y%14===0?'#a7a69e':'#bbbcb4';
        g.beginPath(); g.moveTo(0,y); g.lineTo(1100,y+7);g.stroke();
      }
    }
    if(!['blank','woven'].includes(kind)) {
      g.save();
      if(kind==='skew'){g.translate(540,410);g.rotate(-9*Math.PI/180);g.translate(-540,-410);}
      g.fillStyle=dark?'#a8a59b':'#f6f4ef';
      g.fillRect(165,120,770,600);
      g.fillStyle=dark?'#515048':'#242524';
      g.font=kind==='skew'?'26px Arial':'bold 46px Arial';
      const lines=kind==='sections'
        ? ['DIŞ KUMAŞ','80% PAMUK','20% POLYESTER','ASTAR','100% VİSKON']
        :kind==='year'?['2026 COTTON']
        :kind==='writing-en'?['PLEASE CLOSE THE DOOR']
        :kind==='writing-tr'?['BUGÜN HAVA GÜZEL']:['80% PAMUK','20% POLYESTER'];
      lines.forEach((t,i)=>g.fillText(t,225,205+i*(kind==='sections'?95:130)));
      g.restore();
    }
    return c.toDataURL('image/png').split(',')[1];
  },kind);
  return Buffer.from(base64,'base64');
}

async function main() {
  const fixtures = getFixtures();
  const browser = await chromium.launch({headless:true,
    ...(process.env.CHROME_EXECUTABLE?{executablePath:process.env.CHROME_EXECUTABLE}:{}),
    args:['--no-sandbox']});
  const context = await browser.newContext({locale:'tr-TR',viewport:{width:390,height:844}});
  const page = await context.newPage();
  const requests=[];
  page.on('request',request=>requests.push({method:request.method(),url:request.url()}));
  const results=[];
  try {
    await page.goto(baseUrl,{waitUntil:'networkidle'});
    await page.evaluate(() => {
      // Observe the unfiltered model output BEFORE Doku's acceptance policy.
      // The normal Doku path, image processing and acceptance gate still run.
      const original=Tesseract.createWorker;
      Tesseract.createWorker=async (...args)=>{
        const worker=await original(...args), recognize=worker.recognize.bind(worker);
        worker.recognize=async (...args)=>{
          const outcome=await recognize(...args);
          if (!window.__benchmarkRaw) window.__benchmarkRaw={rawText:outcome.data.text,confidence:outcome.data.confidence};
          return outcome;
        };
        return worker;
      };
    });
    for(const f of fixtures) {
      let bytes;
      if(synthetic) bytes=await makeSynthetic(page,f.generator);
      else {
        const privatePath=path.resolve(path.dirname(manifestPath),f.imagePath);
        bytes=fs.readFileSync(privatePath);
        assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),f.sha256,
          'Image sha256 mismatch: '+f.id);
      }
      const start=Date.now();
      const picker=page.waitForEvent('filechooser');
      await page.evaluate(() => {window.__benchSelection=dokuOcr.pick(false);});
      await (await picker).setFiles({name:f.id+'.png',
        mimeType:synthetic?'image/png':(f.mimeType||'image/jpeg'),buffer:bytes});
      const photo=await page.evaluate(()=>window.__benchSelection);
      assert.ok(photo?.path,'Image should be decoded: '+f.id);
      let target=photo.path;
      if(f.crop) {
        const edit=await page.evaluate(crop=>dokuOcr.editSafe(window.__benchSelection.path,crop),f.crop);
        assert.equal(edit.code,null,'Crop failed: '+f.id);
        target=edit.photo.path;
      }
      await page.evaluate(()=>{window.__benchmarkRaw=null;});
      const output=await page.evaluate(path=>dokuOcr.recognizeSafe(path,()=>{}),target);
      const raw=await page.evaluate(()=>window.__benchmarkRaw);
      assert.ok(output.observation, 'Diagnostics required: '+f.id);
      assert.equal(output.observation.rawText, raw.rawText, 'Unmodified engine text: '+f.id);
      assert.equal(output.observation.confidence, raw.confidence, 'Engine confidence: '+f.id);
      if(f.id.startsWith('clear-writing-')) {
        assert.equal(output.observation.decision,'noComposition');
        assert.ok(raw.confidence>=45, 'Readable control: '+f.id);
        assert.equal(output.text,null);
      }
      if(['blank','weave'].includes(f.id)) assert.notEqual(output.observation.decision,'candidate');
      const metrics=scoreCase(f,{text:output.text,code:output.code,
        rawText:raw?.rawText||'',elapsedMs:Date.now()-start});
      // Only synthetic data enters CI artifacts; private GT stays in chosen local output.
      // Full, sensitive transcriptions are stored only in the explicitly
      // chosen LOCAL private report; CI always runs with synthetic fixtures.
      results.push({...metrics,group:f.group||'unknown',split:f.split||'synthetic',
        groundTruth:f.groundTruth||'',rawText:raw?.rawText||'',filteredText:output.text||'',
        confidence:output.observation.confidence,decision:output.observation.decision,
         secondReading:output.observation.secondReading||null});
      await page.evaluate(([source,derived])=>{
        dokuOcr.release(source);
        if(derived!==source)dokuOcr.release(derived);
        window.__benchSelection=null;
      },[photo.path,target]);
      console.log('BENCHMARK '+(synthetic?'SYNTHETIC':'PRIVATE')+' '+f.id+
        ': accepted='+metrics.accepted+' pairs='+(metrics.correctPairs??'-')+'/'+
        (metrics.referencePairs??'-')+' CER='+(
          metrics.referenceCharacters? (metrics.characterEdits/metrics.referenceCharacters).toFixed(3):'-'));
    }
    assert.ok(requests.every(r=>['GET','HEAD'].includes(r.method)),'No image/GT upload');
    const aggregate=summarize(results);
    const byGroup=Object.fromEntries([...new Set(results.map(r=>r.group))]
      .map(group=>[group,summarize(results.filter(r=>r.group===group))]));
    const report={schemaVersion:1,kind:synthetic?'synthetic-not-real-accuracy':'real-private',
      realSampleCount:synthetic?0:results.length,
      realAccuracy:synthetic?null:aggregate,
      syntheticAccuracy:synthetic?aggregate:null,
      baseUrl,commit:process.env.OCR_COMMIT_SHA||process.env.GITHUB_SHA||null,
      normalization:'NFC, fold whitespace only, preserve case/diacritics/%/digits',
      notes:synthetic?'Only generated fonts/backgrounds; results NEVER estimate real garment OCR quality':
        'Private authorized photos only; do not upload report or images to public CI',
      aggregate,byGroup,results};
    fs.writeFileSync(path.join(dest,'report.json'),JSON.stringify(report,null,2));
    const asPct=n=>n==null?'n/a':(n*100).toFixed(1)+'%';
    const pairs=[
      ['Positive images',aggregate.positiveCount],
      ['Negative images',aggregate.negativeCount],
      ['CER (accepted result incl. rejects)',asPct(aggregate.cer)],
      ['WER (accepted result incl. rejects)',asPct(aggregate.wer)],
      ['Raw Tesseract CER',asPct(aggregate.rawCer)],
      ['Raw Tesseract WER',asPct(aggregate.rawWer)],
      ['Transcribed controls + labels',aggregate.transcriptionCount],
      ['Raw CER incl. textual negatives',asPct(aggregate.transcriptionRawCer)],
      ['Raw WER incl. textual negatives',asPct(aggregate.transcriptionRawWer)],
      ['Exact percent/fiber pair recall',asPct(aggregate.pairExactRecall)],
      ['Fully correct compositions',asPct(aggregate.fullyCorrectCompositionRate)],
      ['False reject rate',asPct(aggregate.falseRejectRate)],
      ['False accept rate',asPct(aggregate.falseAcceptRate)],
      ['Median latency',aggregate.p50Ms==null?'n/a':aggregate.p50Ms+' ms'],
      ['p95 latency',aggregate.p95Ms==null?'n/a':aggregate.p95Ms+' ms']
    ];
    const table=[
      '# Doku OCR benchmark — '+(synthetic?'SYNTHETIC ONLY':'PRIVATE REAL DATA'),
      '',
      'Numbers are OCR fidelity against explicit ground truth, not app smoke-test pass rates.',
      synthetic?'**Real-label sample count: 0; real OCR accuracy: NOT MEASURED.**':
        '**Sensitive local report; do not upload images/transcriptions publicly.**',
      '',
      '| Metric | Value |','|---|---:|',
      ...pairs.map(([key,value])=>'| '+key+' | '+value+' |'),
      '',
      'Raw transcription measures all explicitly transcribed images, independently of label rejection.',
      'False reject counts only positive labels; rejecting readable non-label writing is correct.',
      '',
      '| Case | Decision | Engine confidence | Raw CER | Raw WER |',
      '|---|---|---:|---:|---:|',
      ...results.map(r=>'| '+r.id+' | '+r.decision+' | '+r.confidence+' | '+
        asPct(r.rawTranscription? r.rawTranscription.characterEdits/r.rawTranscription.referenceCharacters:null)+' | '+
        asPct(r.rawTranscription? r.rawTranscription.wordEdits/r.rawTranscription.referenceWords:null)+' |')
    ];
    fs.writeFileSync(path.join(dest,'report.md'),table.join('\n')+'\n');
    console.log('BENCHMARK '+(synthetic?'SYNTHETIC ONLY':'PRIVATE')+' SUMMARY '+JSON.stringify(aggregate));
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch(err=>{
  console.error('::error title=OCR benchmark::'+String(err));
  console.error(err);
  process.exitCode=1;
});
