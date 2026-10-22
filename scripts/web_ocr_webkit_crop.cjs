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
      // Use desktop input in a narrow WebKit viewport: Playwright's mobile
      // WebKit driver cannot issue wheel events to scroll Flutter semantics.
      viewport:{width:390,height:844},isMobile:false,hasTouch:false,
      deviceScaleFactor:2,locale:'tr-TR'
    });
    const page = await context.newPage();
    const pageErrors=[];
    page.on('pageerror',e=>pageErrors.push(e.message));
    try {
      // Reproduce the iPhone report deterministically: corrupt ONLY the
      // Flutter in-memory preview buffers, not the true processed/photo Blob
      // URLs that OCR consumes or the source thumbnail Blob used for crop.
      // This must exercise the browser-native image fallback, not merely a
      // working primary Flutter Image.memory path.
      await page.route('**/doku_ocr.js', async route=>{
        const response=await route.fetch();
        let source=await response.text();
        const marker='const pickSafe = camera => pick(camera).then(photo => ({photo, code: null}),';
        assert.ok(source.includes(marker),'Expected pickSafe bridge marker');
        source=source.replace(marker,
          'const pickSafe = camera => pick(camera).then(photo => { if(photo) { photo.bytes = new Uint8Array([0,1,2,3]); photo.sourceBytes = new Uint8Array([0,1,2,3]); } return {photo, code:null}; },');
        await route.fulfill({response,body:source});
      });
      await page.goto(base,{waitUntil:'networkidle'});
      await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
      // Flutter's semantics tree is lazy on narrow, vertically scrolling
      // pages. Scroll before querying off-screen buttons, as in crop smoke.
      async function button(name) {
        const item=page.getByRole('button',{name,exact:true});
        for(let i=0;i<36 && (await item.count())===0;i++){
          await page.mouse.move(200,520);
          await page.mouse.wheel(0,i<20?260:-220);
          await page.waitForTimeout(75);
        }
        await item.waitFor({timeout:15000});
        await item.click();
      }
      await button('Etiket tara');
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
      await button('Fotoğraf yükle / galeriden seç');
      await (await chooser).setFiles({name:'webkit-photo.png',mimeType:'image/png',buffer:Buffer.from(b64,'base64')});
      // Prove visible real pixels at BOTH boundaries: the preview that will
      // be submitted to OCR and the unmodified source used for cropping.
      // Force Flutter memory decoding to fail for both, so a blank fallback
      // would fail this assertion even if widgets themselves exist.
      async function visibleVioletPixels(fileName) {
        let pixels=0;
        for(let retry=0;retry<12;retry++){
          const screenshot=await page.screenshot();
          fs.writeFileSync(path.join(evidence,fileName),screenshot);
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
        return pixels;
      }
      const scanPixels=await visibleVioletPixels('scan-visible.png');
      assert.ok(scanPixels>100,'WebKit scan preview must show ACTUAL OCR-bound photo pixels, count='+scanPixels);
      assert.equal(await page.getByText(/Fotoğraf önizlemesi açılamadı/).count(),0);
      await button('Fotoğrafı düzenle');
      await page.getByText('Orijinal fotoğraf',{exact:true}).waitFor();
      const pixels=await visibleVioletPixels('crop-visible.png');
      assert.ok(pixels>100,'WebKit crop must show ACTUAL source photo pixels, count='+pixels);
      assert.equal(await page.getByText(/Orijinal fotoğraf gösterilemedi/).count(),0);
      assert.deepEqual(pageErrors,[]);
      console.log('PASS WebKit viewport 390px DPR2: broken Flutter decode buffers; native fallback paints the OCR-bound scan preview ('+scanPixels+' violet pixels) and original crop ('+pixels+' violet pixels)');
    }finally{await context.close();}
  }finally{await browser.close();}
})().catch(e=>{console.error('::error title=WebKit crop visible::',e);process.exitCode=1;});
