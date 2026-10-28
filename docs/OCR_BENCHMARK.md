# Doku — OCR doğruluğunu ölçme (F3-W3)

## Ne ölçüyoruz?

Çalışan OCR akışının görüntüden çıkardığı **ham Tesseract.js metni** ve Doku'nun kullanıcıya **kabul ettiği metin**, görüntüdeki **insanın elle kontrol ettiği doğru transkripsiyon** (ground truth/GT) ile kıyaslanır. **Yapay zekâ/OCR ile üretilmiş tahmin GT değildir.** Metrik motoru ayrı kodda yaşar: `scripts/ocr_benchmark_metrics.cjs`. `scripts/web_ocr_benchmark.cjs` gerçek derlenmiş uygulamanın `dokuOcr.pick -> [editSafe] -> recognizeSafe` yolunu ve worker'ın filtrelenmemiş çıktısını Chromium içinden ölçer; sahte OCR servisi kullanılmaz. Benchmark üretim kararını değiştirmez. F3-W4, aynı kabul filtresini koruyarak ham çıktı/güven/etiket kararını üretim köprüsünde de ayrı taşır; ayrıntılar: [OCR tanıları](OCR_DIAGNOSTICS.md).

**Ölçüm = test geçmesi değildir.** Benchmark'ın düşük skor üretmesi CI hatası olmak zorunda değildir; böylece kötü doğruluk görünmez hale gelmez. Sentetik rapor üretildiğinde “gerçek başarı” iddiası yasaktır.

| Metrik | Anlamı |
|---|---|
| CER | NFC+boşluk sadeleştirme sonrası karakter Levenshtein uzaklığı / GT karakter sayısı. Türkçe İ/ı, rakam, % ve noktalama korunur. Başka şeylerle eşitlenmez |
| WER | Aynı metnin boşlukla ayrılan sözcükleri üzerinde Levenshtein / GT sözcük sayısı |
| raw CER/WER | Filtre reddetse de gerçek Tesseract ham çıktısı ne kadar doğruydu? |
| Pair exact recall | GT'deki **aynı sayı + literal yüzde işareti + aynı elyaf adı** kısa ve bitişik metin olarak okunabildi mi? `8096 PAMUK` ≠ `80% PAMUK` |
| Fully correct composition | Fotoğrafta beklenen bütün elyaf-yüzde çiftleri metinde varsa başarılı; bölüm sahipliğini ve fazladan yanlış çiftleri ölçmez |
| Section-bound exact pair recall | Yalnız insan tarafından `expectedSections` ile işaretlenen etiketlerde, **tam başlığın altındaki** doğru yüzde–elyaf çiftleri / beklenen bölüm çiftleri. Başlık yoksa veya yinelenmişse o bölüm 0; yanlış bölüme taşınmış doğru çift kredi almaz |
| All annotated section pairs recovered | Bölüm başlıklarının her biri tam bir kez geçiyorsa ve beklenen çiftlerin hepsi kendi bölümündeyse başarılı; fazladan yanlış çiftler için ayrıca kesinlik (precision) ölçümü gerekir |
| False reject | Gerçek pozitif etiket fotoğraflarından uygulamanın `emptyText` vb. ile reddettiği oran |
| False accept | İçinde kumaş bileşimi olmayan negatif fotoğraflardan uygulamanın etiket metni diye kabul ettiği oran |
| p50/p95 | Fotoğraf seçimi, görüntü işleme ve OCR dahil geçen sürenin dağılımı, tek CI makinesinde |

CER ve WER **%100'ü aşabilir** (çok sayıda ek karakter); bunları `100 - CER` ile “doğruluk olasılığı” diye sunma. Reddedilen pozitiflerde kullanıcıya sunulan OCR hipotezi boş sayılır; **ham CER** ayrı tutulur. Etiket CER/WER toplamına negatifler katılmaz; bunlarda yanlış kabul ölçülür. F3-W4 ile GT içeren yazılı negatiflerde ayrıca `rawTranscription` CER/WER hesaplanır. `transcriptionRawCer/Wer`, pozitifler ve yazılı negatiflerin ham motor çıktısını birlikte ölçer; `byGroup` bunları ayırır. Boş/doku negatiflerinde GT yoksa bu uzaklık `null` kalır. Etiket olmayan doğru okunmuş cümlenin reddi, false rejection sayılmaz. Makro/mikro farkı önemlidir; ayrıntılar `report.json` içindedir. Tekrarlanan **aynı elyaf+yüzde** GT satırları için aynı sayıda ayrı basılı eşleşme gerekir: tek `80% PAMUK` iki GT satırını karşılamaz. Ayrıca `PAMUK 80% POLYESTER` gibi tek basılı oran iki farklı elyafın ikisine birden doğru eşleşme olarak yazılmaz; iki olası elyafla eşleşiyorsa bu oran benchmark için belirsiz sayılır. Bölüm ölçümü için insanın doğruladığı `expectedSections: [{heading, expectedPairs}]` anotasyonu gerekir; bu bölüm çiftlerinin çoklu kümesi `expectedPairs` ile birebir aynı olmalıdır. Başlıklar satır olarak birebir okunmuş ve benzersiz olmalı; yanlış bölümdeki doğru çift kredi almaz. Bu metrik **recall** ölçer, fazladan yanlış çiftleri yakalayan precision değildir. Bölüm anotasyonu olmayan örnekler sonuçta `null`/kapsam dışıdır; yanlışlıkla başarılı sayılmaz. Bu metrik, kullanıcı onayı veya üretim OCR kararını değiştirmez.

## Sentetik testleri aynı Pages tabanıyla çalıştırma

Depo kökünde Flutter 3.47.7, Node 22, Chromium ve `tool/web_ocr` bağımlılıkları:

```sh
flutter create --platforms=web --project-name etiket .
flutter pub get
npm ci --prefix tool/web_ocr --ignore-scripts --no-audit --no-fund
node scripts/prepare_web_ocr.cjs
node --test scripts/ocr_benchmark_metrics.test.cjs
flutter analyze
flutter test
flutter build web --release --base-href=/etiket/
tool/web_ocr/node_modules/.bin/playwright install chromium
mkdir -p /tmp/doku-benchmark/etiket
cp -a build/web/. /tmp/doku-benchmark/etiket/
python3 -m http.server 8082 --bind 127.0.0.1 --directory /tmp/doku-benchmark
```

Diğer terminalde:

```sh
node scripts/web_ocr_benchmark.cjs http://127.0.0.1:8082/etiket/ --synthetic
```

F3-W4 sentetik kümesi önceki 7 örneği korur; net İngilizce ve Türkçe kontrol cümlesi ekler (4 pozitif, 5 negatif). Her kayıt `rawText`, `confidence`, `decision`, `filteredText` içerir; gerçek worker çıktısıyla köprü alanlarının eşitliği test edilir. `unrelated-year` örneğine de rasteri değiştirmeden açık GT eklenir.

Sentetik `sections-tr` örneği bölüm sahipliğini ayrıca ölçer; bu tek sentetik örnek gerçek bölüm doğruluğu iddiası değildir. Bölüm anotasyonu olmayan diğer örnekler bölüm oranının paydasına girmez. Sentetik rapor: `build/web-ocr-evidence/benchmark-synthetic/report.{json,md}`. Sadece **kod tarafından çizilen** etiket/doku görüntüleri vardır; markalı/özel kullanıcı fotoğrafı veya gizli GT CI artifact'ına konmaz. `realSampleCount: 0`, `realAccuracy: null`. CI benchmark'ı öncelikle ölçüm pipeline'ını sınar, gerçek dünyadaki doğruluk oranını değil.

## OCR bölümleme ve satır kırpma deneyi — gerçek Tesseract.js

`node scripts/web_ocr_roi_matrix.cjs http://127.0.0.1:8082/etiket/` komutu, derlenmiş Web arayüzünün aynı yerel `/etiket/` motor/model dosyalarını kullanarak **gerçek Chromium + Tesseract.js v6** çalıştırır. Önceden çizilmiş, kullanıcıya ait olmayan iki **sentetik** `60% Polyester / 40% Cotton` etiketi üretir; ikinci örnekte dikiş çizgisi ve bakım sembolleri bulunur. Her örneği tam fotoğraf PSM 6/3, yalnız bileşim alanı PSM 6/3/11 ve tek satır PSM 7 olarak ölçer.

Raporlar `build/web-ocr-evidence/roi-matrix.json` ve `roi-matrix.md` içindedir. Karşılaştırma **yalnız gerçek yüzde işareti + birebir elyaf adı** eşleşmelerini sayar; `8096`, `O/0`, yanlış yüzde veya yanlış lif kabul edilmez. Asıl fotoğraf değişmez; ürünün mevcut OCR kararı, manuel düzeltme/onay veya güven eşiği güncellenmez. **Sentetik iki örnekten çıkarılan en iyi PSM gerçek kullanıcı etiketlerinde en iyi PSM anlamına gelmez**. Sonuçlar ancak geliştirme/holdout gerçek fotoğraf setiyle bağımsız ölçüldüğünde üretim davranışı için düşünülebilir. Kullanıcının özel screenshot dosyası GitHub'a/CI artifact'ına konmaz.

## Gerçek fotoğraf veri setini oluşturma (gereken iş)

En az ilk pilot için hedef **50+ izinli gerçek kumaş etiketi, 30+ gerçek negatif**; farklı cihazlar, düşük kontrast, eğiklik, etiket üzerinde dikiş/kat, yüzdeler, Türkçe/İngilizce, astar ve dış kumaş. Veri dağılımı belgelenmeli; en az iki ayrı kişi GT'yi görerek transkribe edip uyuşmazlığı çözmeli; marka/kişisel bilgileri gizlemeli. Aynı kıyafetin fotoğrafları ayrı eğitim/test split'lerine dağıtılmamalı. Geliştirme (dev) ve hiç ayar yapılmayacak holdout seti baştan ayrılmalı. Rakamlar, yüzde ve Türkçe aksanlar GT'de **tam** yazılmalı; okunamayan metin tahmin edilmemeli. Bu minimum pilot büyüklüğü temsiliyet veya güven aralığı garantisi değildir.

Gerçek kullanıcı fotoğrafı, özel GT veya orijinal görüntü **GitHub'a, herkese açık Pages'e, GitHub Actions'e, artifact'a veya analitiğe yüklenmez**. Kullanım izni olmadan görseller kopyalanmaz. Özel gerçek görüntüler ve manifest yalnız kullanıcının kontrolündeki yerel klasörde tutulur. Kodda örnek yapıyı göstermek için kişisel veri içermeyen **manifest şablonu** vardır: `docs/ocr_benchmark_private_example.json`.

Her fotoğrafın manifest kaydı: benzersiz `id`, `kind` (positive/negative), `group`, `split` (dev/holdout), dosyanın kendine ait **SHA-256** değeri, `mimeType`, dosyaya göre göreli `imagePath`, `reviewedByHuman:true`, `usageConsent:true`. Pozitifler için `groundTruth` ve `expectedPairs` (her elyaf/yüzde için); birden çok bölümü olanlarda insan onaylı `expectedSections` (tam basılı `heading` ve o bölüme ait `expectedPairs`), isteğe bağlı `crop` (`left/top/width/height/quarterTurns`, normalize oranlar). Kaynak fotoğraf gerçekten kırpılmadan ve kırpılarak **ayrı kayıtlar/koşullar** olmalı; aynı görsel GT'de yersiz tekrar ağırlık kazanmamalı.

Özel klasörde `manifest.json` ve fotoğrafları oluşturduktan sonra:

```sh
node scripts/web_ocr_benchmark.cjs http://127.0.0.1:8082/etiket/ --manifest /private/doku/manifest.json --out /private/doku/results
```

**`--out` ve özel manifest mutlaka repo/build dışında olsun.** Gerçek benchmark yalnız yerel `http://127.0.0.1` / `localhost` sunucusuyla ve CI dışında çalışır. Çalıştırıcı, fotoğrafların özel manifest klasöründe kalmasını ve sembolik bağlantılarla repo/artifact klasörüne yönlendirilmemesini kontrol eder; harici ağ isteklerini engeller. Bu koruma gerçek fotoğraf benchmarkının yapıldığı anlamına gelmez. Yerel rapor ham OCR metnini ve insan transkripsiyonunu içerebilir; paylaşım istenirse yalnız anonimleştirilmiş toplu metrikleri yayımla. Gerçek veride başarı oranı, `realSampleCount` ve `realAccuracy` doldurulur. OCR karar eşiğini/test verisini otomatik optimize eden kod eklenmemiştir.

## Kalite ve sonraki karar

İlk sonuçları `baseline` olarak dondur. Aynı görüntülerde sabit sürümle `crop` kapalı/açık, sonra düşük ışık ve PSM 3/6/11 karşılaştırmalarını **dev** setinde yap; kör holdout üzerinde ayar yapma. Kritik yanlış yüzde, yanlış elyaf, yanlış bölüm ve yazısız yüzey kabulünü ayrı bildir. İlk gerçek veri gelmeden “OCR %95 doğru” gibi beyanlar kesinlikle yapılmaz.

Kaynak: [OCR-D OCR değerlendirmesi](https://ocr-d.de/en/spec/ocrd_eval.html), [Tesseract görüntü kalitesi](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html), [Tesseract.js 6 API](https://github.com/naptha/tesseract.js/blob/master/docs/api.md). F3-W3: [Issue #14](https://github.com/mehmetyildiz03/etiket/issues/14). Daha geniş kalite borcu: [Issue #11](https://github.com/mehmetyildiz03/etiket/issues/11).
