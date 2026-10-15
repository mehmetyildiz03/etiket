'use strict';
// Real Tesseract.js 6/WASM comparison on SYNTHETIC 60% Polyester / 40% Cotton.
// This is not a product text auto-correction feature or real-photo accuracy.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {chromium}=require('../tool/web_ocr/node_modules/playwright');
const {containsExactPair}=require('./ocr_benchmark_metrics.cjs');
const base=process.argv[2]||'http://127.0.0.1:8082/etiket/';
const out=path.resolve(process.env.OCR_EVIDENCE_DIR||'build/web-ocr-evidence');
fs.mkdirSync(out,{recursive:true});
const pairs=[{percent:'60',fiber:'Polyester'},{percent:'40',fiber:'Cotton'}];
const crops={
  composition:{left:.32,top:.22,width:.50,height:.23,quarterTurns:0},
  line1:{left:.32,top:.24,width:.50,height:.08,quarterTurns:0},
  line2:{left:.32,top:.32,width:.50,height:.08,quarterTurns:0}
};
const variants=[
  ['full-psm6',null,6],['full-psm3',null,3],
  ['composition-psm6','composition',6],['composition-psm3','composition',3],
  ['composition-psm11','composition',11],
  ['first-line-psm7','line1',7],['second-line-psm7','line2',7]
];
async function main(){
 const browser=await chromium.launch({headless:true,
  ...(process.env.CHROME_EXECUTABLE?{executablePath:process.env.CHROME_EXECUTABLE}:{}),
  args:['--no-sandbox']});
 const ctx=await browser.newContext({locale:'tr-TR',viewport:{width:390,height:844}});
 const page=await ctx.newPage(),req=[],results=[];
 page.on('request',r=>req.push(r.method()));
 try{
  // Diagnostic instrumentation in this isolated research browser only:
  // production JS remains unchanged. Preserve the original error stack
  // before dokuOcr maps an unexpected image failure to invalidPhoto.
  await page.route('**/doku_ocr.js', async route => {
    const response=await route.fetch();
    const js=(await response.text()).replaceAll(
      '}).catch(error => { throw error instanceof DOMException',
      '}).catch(error => { globalThis.__roiInternalError=String(error?.stack||error); throw error instanceof DOMException'
    );
    await route.fulfill({response,body:js});
  });
  await page.goto(base,{waitUntil:'networkidle'});
  await page.evaluate(async()=>{
   const a=new URL('./ocr/',location.href);
   window.__studyWorker=await Tesseract.createWorker(['tur','eng'],1,{
    workerPath:new URL('worker.min.js',a).href,corePath:new URL('core/',a).href,
    langPath:new URL('lang/',a).href.replace(/\/$/,''),
    workerBlobURL:false,gzip:true,cachePath:'doku-ocr-6-best-int-v1'});
   await window.__studyWorker.setParameters({preserve_interword_spaces:'1'});
  });
  for(const fixture of ['clean','seamed']){
   const b64=await page.evaluate(kind=>{
    const c=document.createElement('canvas');c.width=1000;c.height=850;
    const g=c.getContext('2d');
    g.fillStyle='#a3a290';g.fillRect(0,0,c.width,c.height);
    for(let y=0;y<c.height;y+=7){
     g.strokeStyle='#838979';g.beginPath();g.moveTo(0,y);
     g.lineTo(1000,y+2);g.stroke();
    }
    g.fillStyle=kind==='clean'?'#f9f8f1':'#e9e6dc';
    g.fillRect(300,150,510,590);
    g.fillStyle='#292929';g.font='bold 36px Arial';
    g.fillText('60% Polyester',334,258);
    g.fillText('40% Cotton',334,334);
    g.strokeStyle='#323232';g.lineWidth=4;
    g.strokeRect(355,450,80,55);
    g.font='28px Arial';g.fillText('30°',372,487);
    g.beginPath();g.arc(548,479,39,0,2*Math.PI);g.stroke();
    g.fillText('P',539,492);
    g.font='bold 26px Arial';g.fillText('Made in Türkiye',350,615);
    if(kind==='seamed'){
     g.globalAlpha=.5;g.strokeStyle='#6f6b68';g.lineWidth=5;
     g.beginPath();g.moveTo(435,170);
     g.bezierCurveTo(401,267,468,320,443,710);g.stroke();
     g.globalAlpha=1;
    }
    return c.toDataURL('image/png').split(',')[1];
   },fixture);
   fs.writeFileSync(path.join(out,'roi-'+fixture+'.png'),Buffer.from(b64,'base64'));
   const choose=page.waitForEvent('filechooser');
   await page.evaluate(()=>{window.__studyPicked=dokuOcr.pick(false)});
   await (await choose).setFiles({name:fixture+'.png',mimeType:'image/png',
      buffer:Buffer.from(b64,'base64')});
   const source=await page.evaluate(()=>window.__studyPicked);
   assert.ok(source&&source.path);
   const urls={full:source.path};
   for(const key of Object.keys(crops)){
    const applied=await page.evaluate(arg=>dokuOcr.editSafe(
      window.__studyPicked.path,arg),crops[key]);
    if (applied.code != null) {
      const diagnostic=await page.evaluate(()=>window.__roiInternalError);
      throw new Error('ROI crop '+key+' failed: '+applied.code+'; root='+diagnostic);
    }
    assert.ok(applied.photo?.path,key);
    urls[key]=applied.photo.path;
   }
   for(const [id,region,psm] of variants){
    const start=Date.now();
    const o=await page.evaluate(async arg=>{
     await window.__studyWorker.setParameters({tessedit_pageseg_mode:String(arg.psm)});
     const data=(await window.__studyWorker.recognize(
       await(await fetch(arg.url)).blob(),{},{text:true})).data;
     return {rawText:data.text,confidence:data.confidence};
    },{psm,url:urls[region||'full']});
    const exp=region==='line1'?pairs.slice(0,1):
      region==='line2'?pairs.slice(1):pairs;
    const found=exp.filter(p=>containsExactPair(o.rawText,p)).length;
    const result={fixture,variant:id,psm,found,expected:exp.length,
       confidence:o.confidence,latencyMs:Date.now()-start,rawText:o.rawText};
    results.push(result);
    console.log('ROI '+fixture+' '+id+': '+found+'/'+exp.length+' '+JSON.stringify(o.rawText.trim().slice(0,110)));
   }
   await page.evaluate(paths=>{
      for(const p of paths)dokuOcr.release(p);
      window.__studyPicked=null;
   },Object.values(urls));
  }
  assert.equal(results.length,2*variants.length);
  assert.ok(req.every(m=>m==='GET'||m==='HEAD'),'no image or text uploads');
  const byVariant=variants.map(([id,region,psm])=>{
   const subset=results.filter(x=>x.variant===id);
   return {variant:id,psm,region:region||'full',
      found:subset.reduce((n,x)=>n+x.found,0),
      expected:subset.reduce((n,x)=>n+x.expected,0),
      meanMs:Math.round(subset.reduce((n,x)=>n+x.latencyMs,0)/subset.length)};
  });
  const report={kind:'SYNTHETIC ONLY',realPhotoCount:0,realAccuracy:null,
    engine:'Real Chromium + Tesseract.js 6 WebAssembly, Turkish/English',
    limits:'Never infer fiber percentages, normalize to 100, or auto-select a higher confidence hypothesis',
    byVariant,results};
  fs.writeFileSync(path.join(out,'roi-matrix.json'),JSON.stringify(report,null,2));
  fs.writeFileSync(path.join(out,'roi-matrix.md'),[
   '# Doku ROI/PSM study — SYNTHETIC ONLY',
   '', 'Two generated labels with 60% Polyester / 40% Cotton and care symbols.',
   '', '| Method | Exact ratios | Mean runtime |','|---|---:|---:|',
   ...byVariant.map(r=>'| '+r.variant+' | '+r.found+'/'+r.expected+' | '+r.meanMs+' ms |'),
   '', 'Not a real photo success rate. No production OCR behavior changed.'
  ].join('\n')+'\n');
 }finally{
  await page.evaluate(async()=>await window.__studyWorker?.terminate()).catch(()=>{});
  await ctx.close();await browser.close();
 }
}
main().catch(e=>{console.error('::error title=OCR ROI research::'+String(e));
console.error(e);process.exitCode=1});
