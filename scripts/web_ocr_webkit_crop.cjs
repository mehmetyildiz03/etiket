'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {webkit} = require('../tool/web_ocr/node_modules/playwright');

// iOS Safari is WebKit, not Chromium. This is an actual compiled Flutter
// Web test, using a synthetic picture and *visible screenshot pixels*.
(async () => {
  const base = process.argv[2] || 'http://127.0.0.1:8082/etiket/';
  const evidence = path.resolve('build/web-ocr-evidence/webkit-crop');
  fs.mkdirSync(evidence, {recursive:true});
  const browser = await webkit.launch({headless:true});
  try {
    const context = await browser.newContext({
      viewport:{width:390,height:844},isMobile:true,hasTouch:true,
      deviceScaleFactor:2,locale:'tr-TR'
    });
    const page = await context.newPage();
    const pageErrors=[];
    page.on('pageerror',e=>pageErrors.push(e.message));
    try {
      await page.goto(base,{waitUntil:'networkidle'});
      await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
      await page.getByRole('button',{name:'Etiket tara',exact:true}).click();
      const b64 = await page.evaluate(()=>{
        const c=document.createElement('canvas'); c.width=1200;c.height=1400;
        const g=c.getContext('2d');
        g.fillStyle='#d1d2cd';g.fillRect(0,0,c.width,c.height);
        g.fillStyle='#a12be2';g.fillRect(120,220,230,850);
        g.fillStyle='white';g.fillRect(415,310,650,540);
        g.fillStyle='#222';g.font='bold 62px Arial';
        g.fillText('60% POLYESTER',440,440);
        g.fillText('40% COTTON',440,550);
        return c.toDataURL('image/png').split(',')[1];
      });
      const chooser=page.waitForEvent('filechooser');
      await page.getByRole('button',{name:'Fotoğraf yükle / galeriden seç',exact:true}).click();
      await (await chooser).setFiles({name:'webkit-photo.png',mimeType:'image/png',buffer:Buffer.from(b64,'base64')});
      await page.getByRole('button',{name:'Fotoğrafı düzenle',exact:true}).click();
      await page.getByText('Orijinal fotoğraf',{exact:true}).waitFor();
      let pixels=0;
      for(let retry=0;retry<12;retry++){
        const screenshot=await page.screenshot();
        fs.writeFileSync(path.join(evidence,'crop-visible.png'),screenshot);
        pixels=await page.evaluate(async(base64)=>{
          const image=new Image();
          image.src='data:image/png;base64,'+base64;
          await image.decode();
          const c=document.createElement('canvas');c.width=image.width;c.height=image.height;
          const ctx=c.getContext('2d',{willReadFrequently:true});
          ctx.drawImage(image,0,0);
          const data=ctx.getImageData(0,0,c.width,c.height).data;
          let n=0;
          for(let i=0;i<data.length;i+=4){
            if(data[i]>130&&data[i]<200&&data[i+1]<85&&data[i+2]>175)n++;
          }
          return n;
        },screenshot.toString('base64'));
        if(pixels>100)break;
        await page.waitForTimeout(250);
      }
      assert.ok(pixels>100,'WebKit crop must show ACTUAL source photo pixels, count='+pixels);
      assert.equal(await page.getByText(/Orijinal fotoğraf gösterilemedi/).count(),0);
      assert.deepEqual(pageErrors,[]);
      console.log('PASS WebKit 390dp: photo is genuinely visible in crop editor ('+pixels+' violet pixels)');
    }finally{await context.close();}
  }finally{await browser.close();}
})().catch(e=>{console.error('::error title=WebKit crop visible::',e);process.exitCode=1;});
