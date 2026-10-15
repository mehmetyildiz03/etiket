# F3-W4 — OCR motor çıktısı ve etiket kararı

[Issue #16](https://github.com/mehmetyildiz03/etiket/issues/16), henüz birleştirilmemiş [PR #15](https://github.com/mehmetyildiz03/etiket/pull/15) üzerine geliştirilmiştir. Başlangıç SHA: `2c10b6414139ced7da32941f3864abbea6ea0903`. PR hedefi main; PR #15 ve bu dal bağımsız olarak mükerrer birleştirilmemelidir. Main'e merge veya Pages deployment bu görevin parçası değildir.

## Ayrı kanıtlar

`web/doku_ocr.js` motor çıktısını kırpmadan/düzeltmeden `observation.rawText` olarak taşır. `confidence` Tesseract'ın 0–100 motor puanıdır; kalibre edilmiş doğruluk olasılığı, etiket geçerliliği veya kumaş kalitesi değildir. Puan geçersiz/yoksa `null` kalır. `decision` aşağıdaki dört sonuçtan biridir:

| Karar | Kanıt ve arayüz | Ayrıştırmaya aday metin |
|---|---|---|
| `noText` | Motor harf/rakam çıkaramadı; boş veya yalnız noktalama. “OCR motoru bu fotoğrafta okunabilir bir metin çıkaramadı.” | Yok |
| `lowConfidence` | Metin var; puan yok veya mevcut kabul eşiğine yetersiz. “Okunan yazı düşük güvenilirlikte; etikete bakarak kontrol et.” Uzun metin de bu kontrolden geçer. | Yok |
| `noComposition` | Yeterli motor puanıyla yazı var, mevcut kumaş filtresi reddetti. “Yazı algılandı, ancak kumaş bileşimi tespit edilemedi.” Metnin hatalı olabileceği ayrıca belirtilir. | Yok |
| `candidate` | Mevcut `plausibleLabelText` filtresi kabul etti. “Okunan metin — henüz doğrulanmadı”. | Ham metnin aynısı, insan incelemesi gerekir |

Mevcut 45 puan ve yüzde işareti olmayan tam elyaf adlarında 65 puan sınırları korunur; yeni bir güven eşiği ayarlanmaz. OCR, fotoğraftaki gerçekte var olmayan harfleri üretebilir; `noComposition` “fotoğrafta kesin yazı var” kanıtı değildir. `noText` de fotoğrafta hiç yazı olmadığını ispatlamaz.

`recognizeSafe` artık `observation` alanı döndürür. Eski `text/code` ve `recognize` string/`emptyText` sözleşmesi korunur; `emptyText` tek başına yeni UI kararının kaynağı değildir. Model yükleme, zaman aşımı, iptal, geçersiz fotoğraf ve aşırı uzun çıktı operasyonel hatadır; bu sonuçlarda `observation:null`. Web adaptörünün isteğe bağlı tanı arayüzü native ML Kit adaptörünü değiştirmez. Native hata kodları ve mevcut mesajları korunur. `label_parser.dart` ve `composition_draft.dart` değiştirilmez.

## Kullanıcı kontrolü ve gizlilik

“OCR'nin okuduğu ham metni göster” düğmesi ham çıktıyı yalnız kullanıcı açarsa widget ağacına ekler. Uyarı: **Ham OCR çıktısı — doğrulanmış kumaş bileşimi değildir**. Motor puanı ve karar ayrı görünür; doku kaynaklı hatalı harfler, yüzde/elyaf tahmini yapılmaması ve tekrar doğrulama gereği açıklanır. Ham metin seçilip kopyalanabilir; panoya otomatik yazılmaz.

Reddedilen çıktı `scan.text` veya draft'a aktarılmaz. Ayrıntıyı açmak onay vermez. “Metin yapıştır” mevcut manuel akışı açar; reddedilen çıktıyı kendiliğinden eklemez. Kabul edilen aday da düzenleme, yüzde doğrulaması ve açık kullanıcı onayından geçer. Kullanıcı düzeltmesinden sonra gecikmiş OCR sonucu hem normal metni hem tanı verisini değiştiremez.

Tanı verisi yeni okuma, fotoğraf seçme (iptal dahil), kırpma/döndürme/sıfırlama, elle düzeltme, iptal, geri/ekrandan ayrılma ve dispose sırasında temizlenir. Sürüm kontrolü eski asenkron sonucu atar. Ayrıntı varsayılan olarak yeniden kapalıdır. Yalnız oturum belleği kullanılır; fotoğraf/ham metin loglanmaz, kalıcı kaydedilmez veya sunucuya yüklenmez. Dil modeli önbelleği kullanıcı verisi içermez.

## Tekrarlanabilir kanıt

Başlangıçta 122 Flutter ve 24 JavaScript testi yeşildi. Çözümden önce eklenen 4 JS beklentisi başarısızdı: ham çıktı/karar kayıptı ve negatif yazılı kontrollerin ham CER/WER ölçümü yoktu. Gerçek derlenmiş başlangıç uygulamasında Chromium/Tesseract `PLEASE CLOSE THE DOOR\n` metnini 95 puan ve CER/WER=0 ile okudu; köprü yalnız `text:null, code:emptyText` döndürdü. Yeni tarayıcı testi eksik `observation` beklentisinde kırmızı oldu.

Yeni testler: dört karar, düşük/eksik/geçersiz güven ve çok uzun çıktı, operasyonel hata ayrımı, native geriye uyumluluk, eski sonuçlar/iptal/geri/yeni fotoğraf/kırpma, opt-in ve manuel düzeltme/onay. Flutter widget akışları 360/390/430 dp ve klavye açıkken çalıştırılır. Önceki 122 Flutter / 24 JS testi aynen korunur.

`node scripts/web_ocr_smoke.cjs http://127.0.0.1:8082/etiket/` mevcut tüm senaryolara ek olarak `web_ocr_diagnostics.cjs` modülünü çalıştırır. Modül ayrı da çalışır:

```sh
node scripts/web_ocr_diagnostics.cjs http://127.0.0.1:8082/etiket/
node scripts/web_ocr_benchmark.cjs http://127.0.0.1:8082/etiket/ --synthetic
```

Gerçek Chromium + Tesseract/WASM, 360 dp İngilizce kontrol, 390 dp Türkçe kontrol, 430 dp etiket, boş ve dokulu yüzey örnekleriyle çalışır. Worker yalnız gözlemlenir; çıktı değiştirilmez veya sahte servisle üretilmez. Köprü ham metni/puanı worker ile birebir karşılaştırılır; ham çıktının opt-in oluşu, ret sonrası manuel girişin boş kalması ve adayın zorunlu onayı sınanır. `/etiket/ocr/` worker/core/TR/EN modellerinin HTTP 200 yüklenmesi ve yalnız GET/HEAD ağ istekleri denetlenir.

CI artifact'ında `diagnostics-report.json`, sentetik görüntüler/ekran görüntüleri ve `benchmark-synthetic/report.{json,md}` bulunur. Raporlar yalnız sentetik, kişisel veri içermeyen örnekleri kaydeder. Özel fotoğraf benchmark prosedürü ve metrikler: [OCR_BENCHMARK.md](OCR_BENCHMARK.md). Final exact SHA, CI bağlantıları ve APK artifact bilgileri PR açıklamasında verilir.

2026-10-15 yerel ölçümü: Flutter analyze temiz, **142/142 Flutter**, **28/28 JS**; Web release ve Android debug APK derlendi. Chrome Headless Shell 141 + Tesseract 6.0.1 ile kontrol cümlelerinde ham CER/WER=0; İngilizce güven puanı 95, Türkçe 96, ikisi de `noComposition`. Çizilmiş net etikette 95 puanla `candidate`, boşta 0 puanla `noText`. Mevcut smoke'un dokulu yüzeyinde hayali harfler 36 puanla `lowConfidence` olarak ayrıldı.

Dokuz örnekli sentetik benchmark'ta etiketler için ham CER %12,5 / WER %23,8; ret dahil sunulan metin CER %21,7 / WER %28,6; yanlış ret **1/4**, yanlış kabul **0/5**. Net yazılı üç negatifte ham CER/WER=0; toplam 7 transkripsiyonun ham CER'i %8,9 / WER'i %16,7. Küçük/eğik pozitif, motor puanı 84 olmasına rağmen hatalı okundu ve filtre tarafından reddedildi; puanın doğruluk garantisi olmadığı somut olarak görülür. Bu küçük sentetik kümeden gerçek fotoğraf başarı yüzdesi çıkarılmaz. Süreler makineye bağlıdır ve artifact raporunda tutulur.

## Açık sınırlamalar

Gerçek kullanıcı fotoğraf veri seti yoktur: `realSampleCount:0`, `realAccuracy:null`. Çizilmiş etiket örneği gerçek kıyafet fotoğrafı değildir. Kontrol cümlesinin doğru okunması genel OCR doğruluk oranı göstermez. Küçük/eğik/dokulu örneklerde yanlış okuma ve yanlış ret sürer; güven puanı bunu her zaman yakalayamaz. Mevcut filtreden geçmiş hatalı yüzde/bölüm/elyaf da mümkündür. Bu görev filtreyi iyileştirmez veya genel amaçlı OCR ürünü yapmaz. Gerçek veri ve bölüm eşleşmesi borçları: [#11](https://github.com/mehmetyildiz03/etiket/issues/11), [#14](https://github.com/mehmetyildiz03/etiket/issues/14).

Tarayıcı otomasyonu fiziksel telefon kamera/klavye veya iOS testi değildir. Android APK derlemesi işlevsel cihaz testi anlamına gelmez. iOS build/cihaz doğrulaması yapılmamıştır. `/etiket/` dosya yüklemesi yerel statik sunucuda ve PR CI'da sınanır; yeni kod kullanıcı onayı olmadan canlı Pages'e yayımlanmaz.
