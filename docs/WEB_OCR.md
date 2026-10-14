# Doku — Tarayıcıda fotoğraf OCR (F3-W1)

Fotoğraf seçilir, önizlenir ve **Fotoğraftaki metni oku** ile tarayıcının içinde okunur. Ham metin **Metni incele ve düzelt** ekranında düzenlenebilir. Ayrıştırma ve bileşim taslağı F2-R1 kodudur; her kumaş bölümünde ayrı %100 ve **Etiketle karşılaştırdım ve doğruladım** onayı gerekir. `7O%`, bilinmeyen lif veya eksik oran sessizce tamamlanmaz. Demo ayrı ve açıkça işaretlidir.

Bu çalışma PR #6 / `296368b61e03d49e23360012e3e062d7be7a5a81` üzerine kuruludur. #6 merge olana kadar main hedefli PR birleşik diff içerir. Android/iOS fabrikası ML Kit adaptörünü kullanmaya devam eder; Web'de native `dart:io`/ML Kit yüklenmez.

## Teknoloji, sürümler ve lisans

- **Tesseract.js 6.0.1**, **tesseract.js-core 6.0.0**: ücretsiz Apache-2.0; LSTM WebAssembly, ayrı Worker. SIMD ve SIMD olmayan LSTM çekirdekleri birlikte sunulur. Resmi `.wasm.js` dosyaları WASM baytlarını içinde taşır; ayrıca bağımsız `.wasm` dosyaları da artifact'ta bulunur.
- **@tesseract.js-data/eng ve /tur 1.0.0**, `4.0.0_best_int`: İngilizce/Türkçe Latin modeller. Kaynak [naptha/tessdata](https://github.com/naptha/tessdata); upstream [tessdata_best](https://github.com/tesseract-ocr/tessdata_best). npm paket metadata lisansı MIT; upstream model deposu Apache-2.0. Lisans/attribution dosyaları assets ile dağıtılır.
- `dart:js_interop` ve doğrudan **package:web 1.1.1** bağımlılığı. Köprü, JS hata nesnesine Dart runtime tür kontrolü uygulamak yerine tipli sonuç/hata kodu döndürür.
- Test sürücüsü **Playwright 1.56.1** (Apache-2.0), yalnızca geliştirme/CI bağımlılığıdır.
- Varsayılan Roboto Regular/Bold, doğrulanan Flutter SDK material-fonts paketinden lisansıyla birlikte eklenmiştir. Renderer ve bu fontlar da aynı statik adresten yüklenir; ağ engeline takılan CDN fallback'i ana akışı durdurmaz.

`tool/web_ocr/package-lock.json` npm paket sürümlerini ve bütünlük hash'lerini sabitler. Kurulum scriptleri kapalıdır. `scripts/prepare_web_ocr.cjs` yalnızca gerekli public motor/modelleri `web/ocr/` altına kopyalar, SHA-256 manifest ve lisansları üretir. Üretilen büyük dosyalar Git'e eklenmez; Web artifact'ına dahil edilir. Motor çalışma anında CDN veya OCR API kullanmaz.

## Kurulum ve /etiket/ kontrolü

Node 22 ve `.flutter-version` içindeki Flutter ile depo kökünde:

```sh
flutter pub get
npm ci --prefix tool/web_ocr --ignore-scripts --no-audit --no-fund
node scripts/prepare_web_ocr.cjs
node --test scripts/web_ocr_bridge.test.cjs
flutter analyze
flutter test
flutter build web --release --base-href=/etiket/
flutter build apk --debug
mkdir -p /tmp/doku-pages/etiket
cp -a build/web/. /tmp/doku-pages/etiket/
python3 -m http.server 8082 --bind 127.0.0.1 --directory /tmp/doku-pages
```

Başka terminalde:

```sh
tool/web_ocr/node_modules/.bin/playwright install chromium
node scripts/web_ocr_smoke.cjs http://127.0.0.1:8082/etiket/
```

Hazır sistem Chromium'u için `CHROME_EXECUTABLE=/usr/bin/chromium` kullanılabilir. Kanıtlar `build/web-ocr-evidence/` altında sentetik görüntü, ham OCR, mobil/masaüstü ekran görüntüleri ve ağ/akış raporlarıdır. Actions aynı scripti gerçek derlenmiş app üzerinde çalıştırır; artifact indirilebilir. `flutter create --platforms=web ...` mevcut özel index/bootstrap/köprü dosyalarını korur; OCR assets kopyalama adımı create'den sonra çalışır.

Canlı Pages yayımlandığında DevTools Network'te `/etiket/ocr/worker.min.js`, `/etiket/ocr/core/tesseract-core-*-lstm.wasm.js`, `/etiket/ocr/lang/{tur,eng}.traineddata.gz` için 200 beklenir. Model cache'i doluysa dil dosyası isteği olmayabilir. Fotoğraf yükleyip sonucu düzelt; her bölümün yüzdesini ayrı incele ve onay kutusu olmadan devam edilemediğini kontrol et. Network'te fotoğraf/metin için POST/upload bulunmamalıdır. Bu PR merge/deploy edilmediğinden yeni kod canlı Pages adresinde yayımlanmış gibi raporlanmaz; aynı `/etiket/` dizin yapısı statik yerel servis ve CI artifact'ı üzerinde doğrulanır.

## İlk indirme, çevrimdışı kullanım ve gizlilik

İlk okumada yaklaşık **9 MB** motor/model verisi gerekir (tarayıcı cache'i ve sunucu sıkıştırmasına bağlı). İnternet gerekir; telefonun işlemcisine göre bekleme değişir. Durum Türkçe gösterilir. Model/worker yükleme hatasında tekrar deneme, metin yapıştırma ve elle giriş çalışır. Worker 120 saniyede sonuç vermezse kapatılıp hata gösterilir.

Dil modelleri IndexedDB'de public model verisi olarak cache'lenebilir. Açık sayfada hazır worker ile çevrimdışı yeni fotoğraf OCR'si test edilmiştir. **İlk kullanım veya sayfayı kapatıp çevrimdışı yeniden açmak garanti değildir**: worker/core/Flutter kaynakları için HTTP cache gerekir; PWA/offline dağıtımı bu görevin kapsamı değildir. Cache silinmesi veya tarayıcının depolamayı kısıtlaması yeniden internet gerektirebilir.

Fotoğraf ve OCR metni sunucuya gönderilmez. Yalnız public uygulama/motor/model dosyaları indirilir; servis anahtarı, OCR backend'i, analitik, üyelik veya ücretli API yoktur. Fotoğraf normalize edilip JPEG Blob olarak bellekte tutulur; EXIF aktarılmaz. Blob URL'leri, canvas ve image kaynakları temizlenir. OCR iptali/model hatası worker'ı başlangıç sırasında da durdurur. Worker başarılı okumalar arasında tekrar kullanılır, sayfa/app kapatıldığında sonlandırılır. Fotoğraf bırakılırken referanslar kaldırılır; OCR/metin kalıcı kayda yazılmaz. BFCache dönüşünde fotoğraf korunabilir; worker yeniden başlatılır.

Tesseract 6 worker handle'ını model hazırlanınca verir. Köprü, **yalnız createWorker çağrısının senkron constructor kısmında**, Worker constructor'ını yakalayıp `finally` ile hemen geri koyar. Bu, ilk model indirmesi sırasında iptal/hata olduğunda gerçek worker'ı da kapatır; sürüm sabittir ve köprü testleri constructor'ın geri konmasını doğrular.

## Tarayıcı/kamera sınırları

Modern WebAssembly/Worker/File API destekli tarayıcı gerekir. Linux Chromium 154.0.8037.57 ile doğrulandı; fiziksel Android Chrome, iOS Safari ve Firefox bu ortamda doğrulanmadı. Desteklenmeyen OCR ortamında manuel/metin akışı kalır.

Güvenli bağlamdaki mobil tarayıcıya `accept="image/*" capture="environment"` sistem seçicisi sunulur. HTTPS Pages güvenli bağlamdır; HTTP localhost test için güvenli kabul edilir. Capture davranışı tarayıcı/OS'ye bağlıdır, canlı video önizlemesi yoktur. Masaüstünde kamera düğmesi gösterilmez; **Fotoğraf yükle / galeriden seç** her zaman alternatiftir. İzin hataları Türkçe gösterilir. Bazı OS seçicileri kamera izni reddini sadece seçim iptali olarak bildirir; uygulama olmayan bir izin durumunu tahmin etmez.

JPEG, PNG, WebP: en fazla **20 MiB / 24 milyon piksel**. Encoded boyutlar decode'dan önce kontrol edilir; uzun kenar en fazla 2400 px'ye küçültülür. HEIC/PDF desteklenmez; JPG/PNG'ye dönüştürmek gerekir. En fazla 20.000 ham karakter. Silik, eğri, yansımalı, küçük yazılı veya dokulu gerçek etiketlerde hata olabilir; bakım sembolleri okunmaz ve doğruluk yüzdesi iddia edilmez.

## Test kanıtı ve sınırlar

- F3-R1 başlangıç **88/88** testi geçti; eski testler değiştirilmedi. Web adaptörü ve mobil/masaüstü widget akışıyla toplam **104** Flutter testi, ayrıca **9** JavaScript köprü testi. İptal edilen eski worker'ın yeni taramayı durdurması önce başarısız testle gösterilip oturum kontrolüyle düzeltildi.
- Gerçek tarayıcı testi: 360/390/430 mobil viewport ve 1280 masaüstü, sentetik Türkçe/İngilizce etiket PNG'si; gerçek Worker + WASM + iki model statik `/etiket/` altından yüklenir. OCR metni `70% PAMUK`, `30% POLYESTER`, `100% VİSKON` içerir. Ham metin elle düzeltilir, dış kumaş/astar ayrı kalır ve onay zorunludur. Başarı akışında console error, başarısız ağ isteği veya upload görülmez.
- Ek tarayıcı hata/iptal kanıtları `safety-report.json` içindedir. Seçici cancel olayı ve izin reddi kontrollü olarak tetiklenir; fiziksel kamera izni testi sayılmaz. Model hatası gerçek model HTTP isteklerinin engellenmesiyle, geç iş iptali gerçek core yüklemesinin geciktirilmesiyle sınanır.
- Gerçek kullanıcı fotoğrafı, fiziksel telefon/kamera, iOS derleme ve canlı Pages yayını **yapılmadı**. Viewport testi, gerçek cihaz/OS klavye davranışını kanıtlamaz; klavye açıkken erişilebilir düğmeler Flutter widget testlerinde kontrol edilir.
- CI'daki Android debug APK artifact'ı telefonda native regresyon testi için kullanılabilir. Native OCR sonuç doğruluğu/izinleri hâlâ cihazda ayrıca denenmelidir.
