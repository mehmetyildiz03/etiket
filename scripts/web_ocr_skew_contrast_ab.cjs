'use strict';
// D4.2 controlled A/B: real Chromium/Tesseract WASM, GENERATED labels only.
// Diagnostic experiment; NEVER selects OCR text, percentages, or fibers in Doku.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('../tool/web_ocr/node_modules/playwright');
const {textDistance, containsExactPair} = require('./ocr_benchmark_metrics.cjs');
const base = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
const out = path.resolve('build/web-ocr-evidence');
const truth = '80% PAMUK\n20% POLYESTER';
const pairs = [{percent:'80',fiber:'PAMUK'},{percent:'20',fiber:'POLYESTER'}];
// Include both rotation directions, a smaller skew, and an unrotated
// textured negative control. All fixtures are generated at test time.
const fixtures = [
  {id:'small-skew-9deg', angle:-9, font:26, faint:false, woven:true},
  // Matched camera-defocus negative control: same text, crop and angle.
  {id:'small-skew-9deg-defocus', angle:-9, font:26, faint:false, woven:true, blurPx:1.25},
  // Same pixels and geometry at a stronger blur; report non-monotonic OCR too.
  {id:'small-skew-9deg-defocus-strong', angle:-9, font:26, faint:false, woven:true, blurPx:2.5},
  {id:'small-skew-plus-9deg', angle:9, font:26, faint:false, woven:true},
  {id:'small-skew-minus-6deg', angle:-6, font:26, faint:false, woven:true},
  {id:'small-straight-woven', angle:0, font:26, faint:false, woven:true},
  {id:'small-low-contrast', angle:0, font:26, faint:true, woven:false}
];
const crop = {left:.14, top:.12, width:.74, height:.76, quarterTurns:0};
async function main() {
  const browser = await chromium.launch({headless:true,
    ...(process.env.CHROME_EXECUTABLE ? {executablePath:process.env.CHROME_EXECUTABLE} : {}),
    args:['--no-sandbox']});
  const context = await browser.newContext({locale:'tr-TR',viewport:{width:390,height:844}});
  const page = await context.newPage();
  const requests = [], results = [];
  page.on('request',r=>requests.push({method:r.method(),url:r.url()}));
  try {
    await page.goto(base,{waitUntil:'networkidle'});
    // Study-only helper is injected into the test page, never into shipped Doku.
    await page.addScriptTag({path:path.join(__dirname,'d4_skew_components.cjs')});
    await page.evaluate(async()=>{
      const assets = new URL('./ocr/',location.href);
      window.__abWorker = await Tesseract.createWorker(['tur','eng'],1,{
        workerPath:new URL('worker.min.js',assets).href,
        corePath:new URL('core/',assets).href,
        langPath:new URL('lang/',assets).href.replace(/\/$/,''),
        workerBlobURL:false,gzip:true,cachePath:'doku-ocr-6-best-int-v1'
      });
      await window.__abWorker.setParameters({preserve_interword_spaces:'1'});
    });
    let sharpReferenceEncoded=null;
    for (const fixture of fixtures) {
      const encoded = await page.evaluate(f=>{
        const canvas=document.createElement('canvas');
        canvas.width=1100;canvas.height=850;
        const c=canvas.getContext('2d');
        c.fillStyle=f.faint?'#686660':'#ebe9e0';
        c.fillRect(0,0,1100,850);
        // Match the woven-background skew-small fixture in web_ocr_benchmark:
        // a clean white label alone is an unrealistically easy deskew test.
        if (f.angle !== 0 || f.woven) {
          for(let y=0;y<850;y+=7) {
            c.strokeStyle=y%14===0?'#a7a69e':'#bbbcb4';
            c.beginPath();c.moveTo(0,y);c.lineTo(1100,y+7);c.stroke();
          }
        }
        c.save();
        c.translate(550,425);c.rotate(f.angle*Math.PI/180);c.translate(-550,-425);
        c.fillStyle=f.faint?'#a8a59b':'#f6f4ef';
        c.fillRect(165,120,770,600);
        if(f.woven) {
          // Subtle stitch lines inside the label challenge the projection
          // estimator without using any private camera imagery.
          c.strokeStyle='#d8d6cf';
          c.lineWidth=1;
          for(let y=126;y<718;y+=11) {
            c.beginPath();c.moveTo(170,y);c.lineTo(930,y+2);c.stroke();
          }
        }
        c.fillStyle=f.faint?'#515048':'#242524';
        c.font=f.font+'px Arial';
        c.fillText('80% PAMUK',225,205);
        c.fillText('20% POLYESTER',225,335);
        c.restore();
        // Apply optical-style defocus to the WHOLE generated camera frame,
        // not just text; preserve source geometry and the same crop/PSM paths.
        if(f.blurPx) {
          const blurred=document.createElement('canvas');
          blurred.width=canvas.width;blurred.height=canvas.height;
          const b=blurred.getContext('2d');
          b.filter='blur('+f.blurPx+'px)';
          b.drawImage(canvas,0,0);
          return blurred.toDataURL('image/png').split(',')[1];
        }
        return canvas.toDataURL('image/png').split(',')[1];
      },fixture);
      if(fixture.id==='small-skew-9deg') sharpReferenceEncoded=encoded;
      if(fixture.blurPx) assert.notEqual(encoded,sharpReferenceEncoded,
        'Defocus fixture must differ in source pixels from its sharp pair');
      const picker=page.waitForEvent('filechooser');
      await page.evaluate(()=>{window.__abPick=dokuOcr.pick(false);});
      await (await picker).setFiles({name:fixture.id+'.png',mimeType:'image/png',
        buffer:Buffer.from(encoded,'base64')});
      const source=await page.evaluate(()=>window.__abPick);
      assert.ok(source?.path,'Production photo decode failed');
      const edited=await page.evaluate(async region=>{
        const picked=await window.__abPick;
        return dokuOcr.editSafe(picked.path,region);
      },crop);
      assert.equal(edited.code,null,'Production crop failed');
      assert.ok(edited.photo?.path);
      // CRITICAL CONTROL: editSafe() ALREADY runs production straightenLabel()
      // and enlarges the crop. Estimating the ORIGINAL camera skew from
      // edited.photo.path would therefore be a double-deskew experiment.
      // Keep the production crop as its own baseline, but derive all study
      // transforms from this untouched, normalized raw source ROI.
      const rawCropUrl=await page.evaluate(async ({sourceUrl,region})=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=Math.max(1,Math.round(img.naturalWidth*region.width));
        canvas.height=Math.max(1,Math.round(img.naturalHeight*region.height));
        const c=canvas.getContext('2d');
        c.drawImage(img,img.naturalWidth*region.left,img.naturalHeight*region.top,
          img.naturalWidth*region.width,img.naturalHeight*region.height,
          0,0,canvas.width,canvas.height);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('raw ROI encode failed')),'image/png'));
        return URL.createObjectURL(blob);
      },{sourceUrl:source.path,region:crop});
      // Isolated A/B threshold candidate, from the SAME raw crop pixels.
      // Never passed to the production acceptance path.
      const contrastUrl=await page.evaluate(async sourceUrl=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth*2;canvas.height=img.naturalHeight*2;
        const c=canvas.getContext('2d',{willReadFrequently:true});
        c.imageSmoothingEnabled=true;
        c.drawImage(img,0,0,canvas.width,canvas.height);
        const image=c.getImageData(0,0,canvas.width,canvas.height);
        for(let p=0;p<image.data.length;p+=4) {
          const gray=.299*image.data[p]+.587*image.data[p+1]+.114*image.data[p+2];
          const value=gray<130?0:255;
          image.data[p]=image.data[p+1]=image.data[p+2]=value;
        }
        c.putImageData(image,0,0);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('threshold encode failed')),'image/png'));
        return URL.createObjectURL(blob);
      },rawCropUrl);
      // Oracle deskew is an upper-bound diagnostic: the fixture generator
      // knows the exact rotation. Production does NOT know this angle and
      // must not automatically apply or select this candidate.
      const deskewUrl=await page.evaluate(async ({sourceUrl,angle})=>{
        const img=new Image();
        img.src=sourceUrl;
        await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth*2;
        canvas.height=img.naturalHeight*2;
        const c=canvas.getContext('2d');
        c.fillStyle='#f6f4ef';
        c.fillRect(0,0,canvas.width,canvas.height);
        c.imageSmoothingEnabled=true;
        c.imageSmoothingQuality='high';
        c.translate(canvas.width/2,canvas.height/2);
        c.rotate(-angle*Math.PI/180);
        c.drawImage(img,-canvas.width/2,-canvas.height/2,canvas.width,canvas.height);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('deskew encode failed')),'image/png'));
        return URL.createObjectURL(blob);
      },{sourceUrl:rawCropUrl,angle:fixture.angle});
      // Matched 2x interpolation control: identical source, canvas size,
      // fill and smoothing to oracle deskew, but no rotation. This isolates
      // the contribution of geometric correction from mere enlargement.
      const upscaleUrl=await page.evaluate(async sourceUrl=>{
        const img=new Image();
        img.src=sourceUrl;
        await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth*2;
        canvas.height=img.naturalHeight*2;
        const c=canvas.getContext('2d');
        c.fillStyle='#f6f4ef';
        c.fillRect(0,0,canvas.width,canvas.height);
        c.imageSmoothingEnabled=true;
        c.imageSmoothingQuality='high';
        c.drawImage(img,0,0,canvas.width,canvas.height);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('upscale encode failed')),'image/png'));
        return URL.createObjectURL(blob);
      },rawCropUrl);
      // Study-only 2x unsharp-mask candidate. The 3x3 blur and gain are
      // fixed before inspecting OCR results; no OCR text, oracle angle or
      // composition percentages influence this transform. Textured seams
      // may be amplified too, so report regressions alongside any gains.
      const focusControl = ['small-skew-9deg', 'small-skew-9deg-defocus',
        'small-skew-9deg-defocus-strong'].includes(fixture.id);
      const unsharp = focusControl ? await page.evaluate(async sourceUrl=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth*2;canvas.height=img.naturalHeight*2;
        const c=canvas.getContext('2d',{willReadFrequently:true});
        c.fillStyle='#f6f4ef';c.fillRect(0,0,canvas.width,canvas.height);
        c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';
        c.drawImage(img,0,0,canvas.width,canvas.height);
        const pixels=c.getImageData(0,0,canvas.width,canvas.height);
        const source=new Uint8ClampedArray(pixels.data);
        const w=canvas.width,h=canvas.height,gain=1.25;
        let changedPixels=0;
        for(let y=1;y<h-1;y++) for(let x=1;x<w-1;x++) {
          const i=(y*w+x)*4;
          let changed=false;
          for(let channel=0;channel<3;channel++) {
            let sum=0;
            for(let dy=-1;dy<=1;dy++) for(let dx=-1;dx<=1;dx++)
              sum+=source[((y+dy)*w+x+dx)*4+channel];
            const next=Math.max(0,Math.min(255,Math.round(
              source[i+channel]+gain*(source[i+channel]-sum/9))));
            if(next!==source[i+channel]) changed=true;
            pixels.data[i+channel]=next;
          }
          if(changed) changedPixels++;
        }
        c.putImageData(pixels,0,0);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('unsharp encode failed')),'image/png'));
        return {url:URL.createObjectURL(blob),changedPixels};
      },rawCropUrl) : null;
      if(focusControl) assert.ok(unsharp.changedPixels>0,
        'Unsharp A/B must actually change the source pixels');
      // Estimate line skew from image pixels, NOT the synthetic fixture angle.
      // A dark-pixel horizontal projection is a small, local candidate for
      // evaluating whether geometry can be inferred without an oracle.
      // Study only: do not wire into production or select OCR text automatically.
      const estimated=await page.evaluate(async sourceUrl=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const sample=document.createElement('canvas');
        sample.width=img.naturalWidth;sample.height=img.naturalHeight;
        const sc=sample.getContext('2d',{willReadFrequently:true});
        sc.drawImage(img,0,0);
        const rgba=sc.getImageData(0,0,sample.width,sample.height).data;
        const points=[];
        for(let y=2;y<sample.height-2;y+=2) {
          for(let x=2;x<sample.width-2;x+=2) {
            const p=(y*sample.width+x)*4;
            const gray=.299*rgba[p]+.587*rgba[p+1]+.114*rgba[p+2];
            if(gray<110) points.push([x,y]);
          }
        }
        if(points.length<60) return {angle:0,pixels:points.length,usable:false};
        let bestAngle=0,bestScore=-Infinity;
        for(let step=-16;step<=16;step++) {
          const angle=step*.75;
          const slope=Math.tan(angle*Math.PI/180);
          const histogram=new Map();
          for(const [x,y] of points) {
            const row=Math.round((y-slope*x)/3);
            histogram.set(row,(histogram.get(row)||0)+1);
          }
          let score=0;
          for(const count of histogram.values()) score+=count*count;
          if(score>bestScore) {bestScore=score;bestAngle=angle;}
        }
        return {angle:bestAngle,pixels:points.length,usable:true};
      },rawCropUrl);
      // Independent candidate: estimate the text-line slope from connected
      // ink glyphs rather than the full dark-pixel horizontal projection.
      // Its only inputs are the cropped pixels; fixture.angle is NOT passed.
      const componentEstimate=await page.evaluate(async sourceUrl=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;
        const c=canvas.getContext('2d',{willReadFrequently:true});
        c.drawImage(img,0,0);
        return window.__dokuStudySkew.estimate(
          c.getImageData(0,0,canvas.width,canvas.height).data,
          canvas.width,canvas.height);
      },rawCropUrl);
      const makeStudyDeskewUrl=async angle=>page.evaluate(async ({sourceUrl,angle})=>{
        const img=new Image();img.src=sourceUrl;await img.decode();
        const canvas=document.createElement('canvas');
        canvas.width=img.naturalWidth*2;canvas.height=img.naturalHeight*2;
        const c=canvas.getContext('2d');
        c.fillStyle='#f6f4ef';c.fillRect(0,0,canvas.width,canvas.height);
        c.imageSmoothingEnabled=true;c.imageSmoothingQuality='high';
        c.translate(canvas.width/2,canvas.height/2);
        c.rotate(-angle*Math.PI/180);
        c.drawImage(img,-canvas.width/2,-canvas.height/2,canvas.width,canvas.height);
        const blob=await new Promise((resolve,reject)=>
          canvas.toBlob(b=>b?resolve(b):reject(Error('study deskew encode failed')),'image/png'));
        return URL.createObjectURL(blob);
      },{sourceUrl:rawCropUrl,angle});
      const estimatedUrl=await makeStudyDeskewUrl(estimated.angle);
      const componentUrl=await makeStudyDeskewUrl(
        componentEstimate.usable?componentEstimate.angle:0);
      console.log('D4.2 SYNTHETIC component angle '+fixture.id+': '+
        JSON.stringify(componentEstimate));
      console.log('D4.2 SYNTHETIC pixel-only angle estimate '+fixture.id+
        ': '+estimated.angle+' degrees, darkPixels='+estimated.pixels);
      const variants=[
        ['production-full',source.path],
        ['production-crop',edited.photo.path],
        ['study-raw-crop',rawCropUrl],
        ['study-crop-2x-threshold',contrastUrl],
        ['study-crop-2x-unrotated',upscaleUrl],
        ['study-crop-estimated-deskew-2x',estimatedUrl],
        ['study-crop-component-deskew-2x',componentUrl],
        ['study-crop-oracle-deskew-2x',deskewUrl],
        ...(unsharp ? [['study-crop-2x-unsharp',unsharp.url]] : [])
      ];
      try {
        for(const [variant,url] of variants) {
          for(const psm of [3,6,11]) {
            const start=Date.now();
            const reading=await page.evaluate(async ({url,psm})=>{
              await window.__abWorker.setParameters({tessedit_pageseg_mode:String(psm)});
              const blob=await (await fetch(url)).blob();
              const data=(await window.__abWorker.recognize(blob)).data;
              return {rawText:data.text,confidence:data.confidence};
            },{url,psm});
            const distance=textDistance(truth,reading.rawText);
            const exactPairs=pairs.filter(p=>containsExactPair(reading.rawText,p)).length;
            results.push({fixture:fixture.id,variant,psm,estimatedAngle:estimated.angle,
              componentAngle:componentEstimate.angle,
              componentUsable:componentEstimate.usable,
              componentGlyphs:componentEstimate.components,
              oracleAngleForComparisonOnly:fixture.angle,exactPairs,
              referencePairs:pairs.length,
              rawCer:distance.characterEdits/distance.referenceCharacters,
              rawWer:distance.wordEdits/distance.referenceWords,
              latencyMs:Date.now()-start,confidence:reading.confidence,
              rawText:reading.rawText});
            console.log('D4.2 SYNTHETIC '+fixture.id+' '+variant+' PSM'+psm+
              ': exact='+exactPairs+'/2 CER='+results.at(-1).rawCer.toFixed(3));
          }
        }
      } finally {
        await page.evaluate(({original,processed,rawCrop,contrast,deskew,upscale,estimated,component,unsharp})=>{
          dokuOcr.release(original);dokuOcr.release(processed);
          URL.revokeObjectURL(rawCrop);
          URL.revokeObjectURL(contrast);URL.revokeObjectURL(deskew);URL.revokeObjectURL(upscale);URL.revokeObjectURL(estimated);URL.revokeObjectURL(component);if(unsharp) URL.revokeObjectURL(unsharp);window.__abPick=null;
        },{original:source.path,processed:edited.photo.path,rawCrop:rawCropUrl,contrast:contrastUrl,deskew:deskewUrl,upscale:upscaleUrl,estimated:estimatedUrl,component:componentUrl,unsharp:unsharp?.url||null});
      }
    }
    assert.equal(results.length,fixtures.length*8*3+3*3,
      'Nine additional unsharp OCR reads are restricted to matched focus controls');
    assert.ok(requests.every(r=>['GET','HEAD'].includes(r.method)),
      'No POST or private image upload');
    // Pair each candidate with its exact same-source, same-scale control.
    // Report regressions as well as gains; never pick a production OCR winner.
    const angleSweep=fixtures.map(fixture=>{
      const sample=results.filter(r=>r.fixture===fixture.id);
      const estimatedAngle=sample[0].estimatedAngle;
      const componentAngle=sample[0].componentAngle;
      return {
        fixture:fixture.id,
        syntheticAngleOnly:fixture.angle,
        estimatedAngle,
        absoluteAngleErrorDeg:Math.abs(estimatedAngle-fixture.angle),
        componentAngle,componentUsable:sample[0].componentUsable,
        componentGlyphs:sample[0].componentGlyphs,
        componentAbsoluteAngleErrorDeg:Math.abs(componentAngle-fixture.angle),
        comparisons:[3,6,11].map(psm=>{
          const baseline=sample.find(r=>r.psm===psm &&
            r.variant==='study-crop-2x-unrotated');
          const corrected=sample.find(r=>r.psm===psm &&
            r.variant==='study-crop-estimated-deskew-2x');
          const component=sample.find(r=>r.psm===psm &&
            r.variant==='study-crop-component-deskew-2x');
          assert.ok(baseline && corrected && component);
          return {psm,unrotatedExactPairs:baseline.exactPairs,
            estimatedDeskewExactPairs:corrected.exactPairs,
            exactPairDelta:corrected.exactPairs-baseline.exactPairs,
            componentExactPairs:component.exactPairs,
            componentExactPairDelta:component.exactPairs-baseline.exactPairs,
            unrotatedCer:baseline.rawCer,estimatedDeskewCer:corrected.rawCer,
            cerDelta:corrected.rawCer-baseline.rawCer,
            componentCer:component.rawCer,
            componentCerDelta:component.rawCer-baseline.rawCer,
            unrotatedMs:baseline.latencyMs,estimatedDeskewMs:corrected.latencyMs,
            componentMs:component.latencyMs};
        })
      };
    });
    assert.ok(angleSweep.every(x=>Number.isFinite(x.absoluteAngleErrorDeg) &&
      Number.isFinite(x.componentAbsoluteAngleErrorDeg)));
    assert.ok(results.every(r=>Number.isFinite(r.rawCer) && Number.isFinite(r.rawWer)));
    // Report candidate failures and regressions; never assert that it wins.
    for(const row of angleSweep) {
      console.log('D4.2 SYNTHETIC angle-sweep '+row.fixture+
        ' estimated='+row.estimatedAngle+' oracle='+row.syntheticAngleOnly+
        ' absError='+row.absoluteAngleErrorDeg+
        ' component='+row.componentAngle+' componentError='+row.componentAbsoluteAngleErrorDeg+
        ' pairDeltas='+row.comparisons.map(x=>'PSM'+x.psm+':'+x.exactPairDelta).join(','));
    }
    // Paired sharp / mild / stronger blur sweep. Every comparison uses the
    // identical synthetic label, source geometry, ROI, variant and PSM.
    // Do not assume OCR quality degrades monotonically as blur increases.
    const blurLevels=[1.25,2.5];
    const blurImpact=results.filter(x=>
      ['small-skew-9deg-defocus','small-skew-9deg-defocus-strong'].includes(x.fixture))
      .map(blurred=>{
        const sharp=results.find(x=>x.fixture==='small-skew-9deg' &&
          x.variant===blurred.variant && x.psm===blurred.psm);
        assert.ok(sharp,'Missing matched sharp control');
        const blurPx=blurred.fixture==='small-skew-9deg-defocus' ? 1.25 : 2.5;
        return {blurPx,variant:blurred.variant,psm:blurred.psm,
          sharpExactPairs:sharp.exactPairs,blurredExactPairs:blurred.exactPairs,
          exactPairDelta:blurred.exactPairs-sharp.exactPairs,
          sharpCer:sharp.rawCer,blurredCer:blurred.rawCer,
          cerDelta:blurred.rawCer-sharp.rawCer,
          sharpWer:sharp.rawWer,blurredWer:blurred.rawWer,
          werDelta:blurred.rawWer-sharp.rawWer};
      });
    assert.equal(blurImpact.length,blurLevels.length*(8*3+3));
    for(const level of blurLevels) {
      const atLevel=blurImpact.filter(r=>r.blurPx===level);
      assert.equal(atLevel.length,8*3+3,'Each blur level needs every matched variant/PSM');
      for(const row of atLevel) console.log('D4.2 SYNTHETIC defocus '+
        level+'px '+row.variant+' PSM'+row.psm+' exactDelta='+row.exactPairDelta+
        ' cerDelta='+row.cerDelta.toFixed(3)+' werDelta='+row.werDelta.toFixed(3));
    }
    // Compare unsharp against identical 2x interpolation, ROI and PSM.
    // Never treat improved synthetic CER as a calibrated focus score.
    const unsharpImpact=results.filter(x=>x.variant==='study-crop-2x-unsharp')
      .map(sharpened=>{
        const control=results.find(x=>x.fixture===sharpened.fixture &&
          x.psm===sharpened.psm && x.variant==='study-crop-2x-unrotated');
        assert.ok(control,'Missing same-source unsharp control');
        return {fixture:sharpened.fixture,psm:sharpened.psm,
          unrotatedExactPairs:control.exactPairs,
          unsharpExactPairs:sharpened.exactPairs,
          exactPairDelta:sharpened.exactPairs-control.exactPairs,
          unrotatedCer:control.rawCer,unsharpCer:sharpened.rawCer,
          cerDelta:sharpened.rawCer-control.rawCer,
          unrotatedWer:control.rawWer,unsharpWer:sharpened.rawWer,
          werDelta:sharpened.rawWer-control.rawWer};
      });
    assert.equal(unsharpImpact.length,3*3);
    for(const row of unsharpImpact)
      console.log('D4.2 SYNTHETIC unsharp '+row.fixture+' PSM'+row.psm+
        ' exactDelta='+row.exactPairDelta+' cerDelta='+row.cerDelta.toFixed(3)+
        ' werDelta='+row.werDelta.toFixed(3));
    const report={kind:'SYNTHETIC ONLY',realPhotoCount:0,realAccuracy:null,
      purpose:'Compare raw source ROI/production auto-deskew/PSM; no production winner or real accuracy',
      oracleDeskew:'Known synthetic fixture angle only; not deployable angle estimation',
      deskewControl:'All study variants derive from unprocessed raw ROI; editSafe already deskews and upscales production-crop. 2x unrotated matches study interpolation.',
      estimatedDeskew:'Pixel-only horizontal projection, no fixture-angle access; study only',
      componentDeskew:'Pixel-only connected-component centroid estimator; paired with same-source 2x unrotated control; study only',
      commit:process.env.OCR_COMMIT_SHA||process.env.GITHUB_SHA||null,
      engine:'Chromium Tesseract.js WASM tur+eng',
      note:'No automatic selection, no changes to user corrections or approval',
      defocusControl:'Matched sharp/1.25px/2.5px full-frame canvas blur; synthetic camera-defocus proxy only, not a calibrated phone lens',
      blurLevelsPx:blurLevels,
      unsharpControl:'Fixed 2x unsharp 3x3 box kernel, gain 1.25; matched against same-source 2x unrotated, study-only',
      unsharpImpact,blurImpact,angleSweep,results};
    fs.mkdirSync(out,{recursive:true});
    fs.writeFileSync(path.join(out,'d4-2-skew-contrast-ab.json'),JSON.stringify(report,null,2));
  } finally {
    await page.evaluate(async()=>window.__abWorker?.terminate()).catch(()=>{});
    await context.close();await browser.close();
  }
}
main().catch(error=>{
  console.error('::error title=D4.2 OCR A/B::'+String(error));
  console.error(error);process.exitCode=1;
});
