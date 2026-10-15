# Doku — OCR doğruluğunu ölçme (F3-W3)

## Ne ölçüyoruz?

Çalışan OCR akışının görüntüden çıkardığı **ham Tesseract.js metni** ve Doku'nun kullanıcıya **kabul ettiği metin**, görüntüdeki **insanın elle kontrol ettiği doğru transkripsiyon** (ground truth/GT) ile kıyaslanır. **Yapay zekâ/OCR ile üretilmiş tahmin GT değildir.** Metrik motoru ayrı kodda yaşar: `scripts/ocr_benchmark_metrics.cjs`. `scripts/web_ocr_benchmark.cjs` gerçek derlenmiş uygulamanın `dokuOcr.pick -> [editSafe] -> recognizeSafe` yolunu ve worker'ın filtrelenmemiş çıktısını Chromium içinden ölçer; sahte OCR servisi kullanılmaz. Üretim OCR davranışı değiştirilmez.

**Ölçüm = test geçmesi değildir.** Benchmark'ın düşük skor üretmesi CI hatası olmak zorunda değildir; böylece kötü doğruluk görünmez hale gelmez. Sentetik rapor üretildiğinde “gerçek başarı” iddiası yasaktır.

| Metrik | Anlamı |
|---|---|
| CER | NFC+boşluk sadeleştirme sonrası karakter Levenshtein uzaklığı / GT karakter sayısı. Türkçe İ/ı, rakam, % ve noktalama korunur. Başka şeylerle eşitlenmez |
| WER | Aynı metnin boşlukla ayrılan sözcükleri üzerinde Levenshtein / GT sözcük sayısı |
| raw CER/WER | Filtre reddetse de gerçek Tesseract ham çıktısı ne kadar doğruydu? |
| Pair exact recall | GT'deki **aynı sayı + literal yüzde işareti + aynı elyaf adı** kısa ve bitişik metin olarak okunabildi mi? `8096 PAMUK` ≠ `80% PAMUK` |
| Fully correct composition | Fotoğrafta beklenen bütün elyaf-yüzde çiftleri doğruysa başarılı (bu metrik bölüm yerleşimini henüz ölçmez) |
| False reject | Gerçek pozitif etiket fotoğraflarından uygulamanın `emptyText` vb. ile reddettiği oran |
| False accept | İçinde kumaş bileşimi olmayan negatif fotoğraflardan uygulamanın etiket metni diye kabul ettiği oran |
| p50/p95 | Fotoğraf seçimi, görüntü işleme ve OCR dahil geçen sürenin dağılımı, tek CI makinesinde |

CER ve WER **%100'ü aşabilir** (çok sayıda ek karakter); bunları `100 - CER` ile “doğruluk olasılığı” diye sunma. Reddedilen pozitiflerde kullanıcıya sunulan OCR hipotezi boş sayılır; **ham CER** ayrı tutulur. Negatiflerde CER/WER uygulanmaz; yanlış kabul ölçülür. Makro/mikro farkı önemlidir; ayrıntılar `report.json` içindedir. Bölümler arasında aynı lif+yüzde tekrarı veya karmaşık satır sırasının otomatik bölümle eşleşmesi henüz ölçülmüyor: bu ayrı **kritik risk** ve insan onaylı bölüm GT/alan konumlarıyla F3-W3'ün sonraki aşamasında eklenecek.

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

Sentetik rapor: `build/web-ocr-evidence/benchmark-synthetic/report.{json,md}`. Sadece **kod tarafından çizilen** etiket/doku görüntüleri vardır; markalı/özel kullanıcı fotoğrafı veya gizli GT CI artifact'ına konmaz. `realSampleCount: 0`, `realAccuracy: null`. CI benchmark'ı öncelikle ölçüm pipeline'ını sınar, gerçek dünyadaki doğruluk oranını değil.

## Gerçek fotoğraf veri setini oluşturma (gereken iş)

En az ilk pilot için hedef **50+ izinli gerçek kumaş etiketi, 30+ gerçek negatif**; farklı cihazlar, düşük kontrast, eğiklik, etiket üzerinde dikiş/kat, yüzdeler, Türkçe/İngilizce, astar ve dış kumaş. Veri dağılımı belgelenmeli; en az iki ayrı kişi GT'yi görerek transkribe edip uyuşmazlığı çözmeli; marka/kişisel bilgileri gizlemeli. Aynı kıyafetin fotoğrafları ayrı eğitim/test split'lerine dağıtılmamalı. Geliştirme (dev) ve hiç ayar yapılmayacak holdout seti baştan ayrılmalı. Rakamlar, yüzde ve Türkçe aksanlar GT'de **tam** yazılmalı; okunamayan metin tahmin edilmemeli. Bu minimum pilot büyüklüğü temsiliyet veya güven aralığı garantisi değildir.

Gerçek kullanıcı fotoğrafı, özel GT veya orijinal görüntü **GitHub'a, herkese açık Pages'e, GitHub Actions'e, artifact'a veya analitiğe yüklenmez**. Kullanım izni olmadan görseller kopyalanmaz. Özel gerçek görüntüler ve manifest yalnız kullanıcının kontrolündeki yerel klasörde tutulur. Kodda örnek yapıyı göstermek için kişisel veri içermeyen **manifest şablonu** vardır: `docs/ocr_benchmark_private_example.json`.

Her fotoğrafın manifest kaydı: benzersiz `id`, `kind` (positive/negative), `group`, `split` (dev/holdout), dosyanın kendine ait **SHA-256** değeri, `mimeType`, dosyaya göre göreli `imagePath`, `reviewedByHuman:true`, `usageConsent:true`. Pozitifler için `groundTruth` ve `expectedPairs` (her elyaf/yüzde için); isteğe bağlı `crop` (`left/top/width/height/quarterTurns`, normalize oranlar). Kaynak fotoğraf gerçekten kırpılmadan ve kırpılarak **ayrı kayıtlar/koşullar** olmalı; aynı görsel GT'de yersiz tekrar ağırlık kazanmamalı.

Özel klasörde `manifest.json` ve fotoğrafları oluşturduktan sonra:

```sh
node scripts/web_ocr_benchmark.cjs http://127.0.0.1:8082/etiket/ --manifest /private/doku/manifest.json --out /private/doku/results
```

**`--out` mutlaka repo/build dışında olsun.** Yerel rapor ham OCR metnini ve insan transkripsiyonunu içerebilir; paylaşım istenirse yalnız anonimleştirilmiş toplu metrikleri yayımla. Gerçek veride başarı oranı, `realSampleCount` ve `realAccuracy` doldurulur. OCR karar eşiğini/test verisini otomatik optimize eden kod eklenmemiştir.

## Kalite ve sonraki karar

İlk sonuçları `baseline` olarak dondur. Aynı görüntülerde sabit sürümle `crop` kapalı/açık, sonra düşük ışık ve PSM 3/6/11 karşılaştırmalarını **dev** setinde yap; kör holdout üzerinde ayar yapma. Kritik yanlış yüzde, yanlış elyaf, yanlış bölüm ve yazısız yüzey kabulünü ayrı bildir. İlk gerçek veri gelmeden “OCR %95 doğru” gibi beyanlar kesinlikle yapılmaz.

Kaynak: [OCR-D OCR değerlendirmesi](https://ocr-d.de/en/spec/ocrd_eval.html), [Tesseract görüntü kalitesi](https://tesseract-ocr.github.io/tessdoc/ImproveQuality.html), [Tesseract.js 6 API](https://github.com/naptha/tesseract.js/blob/master/docs/api.md). F3-W3: [Issue #14](https://github.com/mehmetyildiz03/etiket/issues/14). Daha geniş kalite borcu: [Issue #11](https://github.com/mehmetyildiz03/etiket/issues/11).
