'use strict';
const {mkdirSync, rmSync, copyFileSync, readFileSync, writeFileSync} = require('node:fs');
const {resolve, join} = require('node:path');
const {createHash} = require('node:crypto');
const root = resolve(__dirname, '..');
const modules = join(root, 'tool/web_ocr/node_modules');
const output = join(root, 'web/ocr');
rmSync(output, {recursive: true, force: true});
mkdirSync(output, {recursive: true});
const hashes = {};
function copy(source, dest) {
  const target = join(output, dest);
  mkdirSync(resolve(target, '..'), {recursive: true});
  copyFileSync(join(modules, source), target);
  hashes[dest] = createHash('sha256').update(readFileSync(target)).digest('hex');
}
copy('tesseract.js/dist/tesseract.min.js', 'tesseract.min.js');
copy('tesseract.js/dist/worker.min.js', 'worker.min.js');
copy('tesseract.js/LICENSE.md', 'licenses/TESSERACT_JS_LICENSE');
copy('tesseract.js/dist/tesseract.min.js.LICENSE.txt', 'tesseract.min.js.LICENSE.txt');
copy('tesseract.js/dist/worker.min.js.LICENSE.txt', 'worker.min.js.LICENSE.txt');
copy('tesseract.js-core/LICENSE', 'licenses/TESSERACT_CORE_LICENSE');
for (const variant of ['lstm', 'simd-lstm']) {
  // wasm.js embeds WASM; also include the standalone WASM for compatible loaders.
  for (const suffix of ['wasm.js', 'wasm']) {
    copy(`tesseract.js-core/tesseract-core-${variant}.${suffix}`, `core/tesseract-core-${variant}.${suffix}`);
  }
}
for (const lang of ['eng', 'tur']) {
  copy(`@tesseract.js-data/${lang}/4.0.0_best_int/${lang}.traineddata.gz`, `lang/${lang}.traineddata.gz`);
}
copyFileSync(join(root, 'tool/web_ocr/NOTICE.txt'), join(output, 'NOTICE.txt'));
writeFileSync(join(output, 'asset-sha256.json'), JSON.stringify(hashes, null, 2) + '\n');
console.log(`Prepared ${Object.keys(hashes).length} pinned OCR assets in web/ocr`);
for (const license of ['TESSDATA_LICENSE', 'TESSDATA_BEST_LICENSE', 'LEPTONICA_LICENSE',
  'REGENERATOR_LICENSE', 'BUFFER_LICENSE', 'IEEE754_LICENSE', 'ZLIB_LICENSE']) {
  copyFileSync(join(root, 'tool/web_ocr', license), join(output, 'licenses', license));
}
