# Doku — Tarayıcıda fotoğraf OCR ve düzenleme (F3-W1 / F3-W2)

Fotoğraf seçilir, önizlenir ve **Fotoğraftaki metni oku** ile tarayıcının içinde okunur. Ham metin **Metni incele ve düzelt** ekranında düzenlenebilir. Ayrıştırma ve bileşim taslağı F2-R1 kodudur; her kumaş bölümünde ayrı %100 ve **Etiketle karşılaştırdım ve doğruladım** onayı gerekir. `7O%`, bilinmeyen lif veya eksik oran sessizce tamamlanmaz. Demo ayrı ve açıkça işaretlidir.

W1 çalışması PR #6 üzerine kurulmuştur. **W2 başlangıcı PR #10 / `87b1de1f9f83f691381c01ccd65916d7bbe4d3a5`**; `codex/f3-w2-crop-rotate` branch’i bu kodu korur. PR #10 üzerindeki ek değişiklikleri de içerir; #10 merge edilene kadar combined diff. İki PR mükerrer birleştirilmemelidir. Android/iOS fabrikası ML Kit adaptörünü kullanmaya devam eder; Web'de native `dart:io`/ML Kit yüklenmez.

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

Fotoğraf ve OCR metni sunucuya gönderilmez. Yalnız public uygulama/motor/model dosyaları indirilir; servis anahtarı, OCR backend'i, analitik, üyelik veya ücretli API yoktur. Orijinal dosya yalnız tarama oturumunda bellekte tutulur; diske/IndexedDB’ye yazılmaz. EXIF tarayıcı tarafından normalize edilir; işlenmiş PNG önizlemesine EXIF aktarılmaz. Yeniden düzenleme daima orijinalden yapılır. Blob URL'leri, canvas ve image kaynakları temizlenir. OCR iptali/model hatası worker'ı başlangıç sırasında da durdurur. Worker aynı fotoğraf oturumundaki başarılı okumalar arasında tekrar kullanılır; son fotoğraf bırakılınca, sayfa/app kapatılınca sonlandırılır (motor belleğindeki son sayfa da bırakılır). Fotoğraf bırakılırken referanslar kaldırılır; OCR/metin kalıcı kayda yazılmaz. BFCache dönüşünde fotoğraf korunabilir; worker yeniden başlatılır.

Tesseract 6 worker handle'ını model hazırlanınca verir. Köprü, **yalnız createWorker çağrısının senkron constructor kısmında**, Worker constructor'ını yakalayıp `finally` ile hemen geri koyar. Bu, ilk model indirmesi sırasında iptal/hata olduğunda gerçek worker'ı da kapatır; sürüm sabittir ve köprü testleri constructor'ın geri konmasını doğrular.

## Tarayıcı/kamera sınırları

Modern WebAssembly/Worker/File API destekli tarayıcı gerekir. Linux Chromium 154.0.8037.57 ve Chrome for Testing 141.0.7390.37 ile doğrulandı; fiziksel Android Chrome, iOS Safari ve Firefox bu ortamda doğrulanmadı. Test sürücüsü `tr-TR` locale kullanır; CI'ın varsayılan locale'i Flutter/Intl başlangıcında `Incorrect locale information provided` hatası oluşturduğu için açıkça sabitlenmiştir. Desteklenmeyen OCR ortamında manuel/metin akışı kalır.

Güvenli bağlamdaki mobil tarayıcıya `accept="image/*" capture="environment"` sistem seçicisi sunulur. HTTPS Pages güvenli bağlamdır; HTTP localhost test için güvenli kabul edilir. Capture davranışı tarayıcı/OS'ye bağlıdır, canlı video önizlemesi yoktur. Masaüstünde kamera düğmesi gösterilmez; **Fotoğraf yükle / galeriden seç** her zaman alternatiftir. İzin hataları Türkçe gösterilir. Bazı OS seçicileri kamera izni reddini sadece seçim iptali olarak bildirir; uygulama olmayan bir izin durumunu tahmin etmez.

JPEG, PNG, WebP: en fazla **20 MiB / 24 milyon piksel**. Encoded boyutlar decode'dan önce kontrol edilir; uzun kenar en fazla 2400 px'ye küçültülür. HEIC/PDF desteklenmez; JPG/PNG'ye dönüştürmek gerekir. En fazla 20.000 ham karakter. Silik, eğri, yansımalı, küçük yazılı veya dokulu gerçek etiketlerde hata olabilir; bakım sembolleri okunmaz ve doğruluk yüzdesi iddia edilmez.

## Okunabilirlik incelemesi (W1 iyileştirmesi)

Gerçek etiketlerde başarısız OCR geri bildirimi üzerine, tam yatay ve büyük harfli sentetik görsellerle sınırlı testlerin yeterli olmadığı görüldü. Yerel Tesseract CLI deneyinde 9° eğik, orta kontrastlı bir etiketin **80% → 0%**, **100% → 3.00%**; hafif bulanık bir etiketin **20% → 2096** gibi okunabildiği gözlendi. Bu deneyler canlı Pages/Tesseract.js sürümü için tek başına kanıt değildir.

Tarayıcıda fotoğrafın **metin doğrultusu** koyu baskı piksellerinin satır projeksiyonuyla yaklaşık ±12° aralığında ölçülür; güçlü kanıt varsa görüntü OCR'den önce döndürülür. Düz veya metni yetersiz fotoğraflar çevrilmez. Gerçek Chromium deneyinde 20px sentetik etiketin yüzde işaretleri **80% → 8096**, **20% → 2096**, **100% → 10096** olarak okunduğundan küçük resimler en fazla iki kat büyütülür; küçük normalleştirilmiş OCR girdisi kayıpsız PNG olarak tutulur. W1 büyük fotoğraflarda JPEG kullanıyordu; W2 işlenen önizlemeyi piksel sınırları içinde kayıpsız PNG tutar. **Okunan metindeki hiçbir rakam/elyaf otomatik düzeltilmez**; kullanıcı hâlâ kaynağa bakıp onaylar. Otomatik doğrultma katlanmış etiket, perspektif bozulması, çok dilli farklı yönlerde metin, ciddi bulanıklık veya parlama için garanti değildir. Bu durumlarda etiketi daha yakından, doğrudan ve aydınlık çekmek veya ham metni elle düzeltmek gerekir.

CI'ın gerçek Chromium/WebAssembly testine orta kontrastlı ve 9° eğik sentetik etiket eklendi; %80, %20 ve %100 değerlerinin korunması beklenir. Gerçek kıyafet fotoğrafları, cihaz kamerası veya farklı fiziksel tarayıcılar ayrıca ölçülmelidir.

## Yazı olmayan yüzeyler ve yanlış OCR harfleri

Tesseract bir **yazı/etiket varlığı sınıflandırıcısı değildir**: kumaş dokusu, gölge, duvar gibi yazısız görüntülerde bile alakasız harfler üretebilir. Web OCR sonucunu artık **doğrulanmış veri değil, güven kontrolünden geçen bir öneri** sayarız. Sonuçta model güveni çok düşükse veya kumaş bileşimine ait bağımsız metinsel ipuçları yoksa uygulama okunabilir etiket bulunamadığını söyleyip yeniden fotoğraf çekme, metin yapıştırma ve elle giriş seçeneklerini korur.

Kontrol gerçek metnin oranını/elyafını **asla uydurmaz veya otomatik düzeltmez**. Tek satır `100% CO`, `80% Pamuk / 20% Polyester` ve belirgin başlıklı bilinmeyen elyaf gibi metinler hâlâ kullanıcı incelemesine açılır. Ancak model çok düşük güvenle gerçek bir etiket okursa da öneriyi reddedebilir; kullanıcı o zaman daha net bir fotoğraf çekebilir veya elle girebilir. Kontrol sahte harfleri tamamen ortadan kaldıracağını garanti etmez; **yanlış pozitifleri azaltmak** içindir. Tekrarlayan gerçek fotoğraflarla ölçüm hâlâ gereklidir.

Tarayıcı regresyonlarına **yazısız düz renk ve yazısız örgü/doku görüntüsü** eklendi. Yalnız sentetik resimler gerçek telefon fotoğraflarının garantisi değildir; gerçek kamerayla test henüz yapılmadı.

## Test kanıtı ve sınırlar

- F3-R1 başlangıç **88/88** testi geçti; eski testler değiştirilmedi. Web adaptörü ve mobil/masaüstü widget akışıyla toplam **104** Flutter testi, ayrıca **9** JavaScript köprü testi. İptal edilen eski worker'ın yeni taramayı durdurması önce başarısız testle gösterilip oturum kontrolüyle düzeltildi.
- Gerçek tarayıcı testi: 360/390/430 mobil viewport ve 1280 masaüstü, sentetik Türkçe/İngilizce etiket PNG'si; gerçek Worker + WASM + iki model statik `/etiket/` altından yüklenir. OCR metni `70% PAMUK`, `30% POLYESTER`, `100% VİSKON` içerir. Ham metin elle düzeltilir, dış kumaş/astar ayrı kalır ve onay zorunludur. Başarı akışında console error, başarısız ağ isteği veya upload görülmez.
- Ek tarayıcı hata/iptal kanıtları `safety-report.json` içindedir. Seçici cancel olayı ve izin reddi kontrollü olarak tetiklenir; fiziksel kamera izni testi sayılmaz. Model hatası gerçek model HTTP isteklerinin engellenmesiyle, geç iş iptali gerçek core yüklemesinin geciktirilmesiyle sınanır.
- Gerçek kullanıcı fotoğrafı, fiziksel telefon/kamera, iOS derleme ve canlı Pages yayını **yapılmadı**. Viewport testi, gerçek cihaz/OS klavye davranışını kanıtlamaz; klavye açıkken erişilebilir düğmeler Flutter widget testlerinde kontrol edilir.
- CI'daki Android debug APK artifact'ı telefonda native regresyon testi için kullanılabilir. Native OCR sonuç doğruluğu/izinleri hâlâ cihazda ayrıca denenmelidir.


## F3-W2: kırpma, yön ve işlenecek görüntü

Web’de **Fotoğrafı düzenle** isteğe bağlıdır. Düzenleyici EXIF yönü normalize edilmiş **orijinal fotoğrafın** küçük önizlemesini gösterir. Köşeler en az 44×44 dp dokunma hedefidir; seçili alan taşınabilir, dışına sürükleyerek yeni alan çizilebilir. Dört yüzde alanı klavye/erişilebilirlik alternatifidir. **90° sola/sağa**, **Sıfırla** (tam orijinal ve 0°), **Kırpmayı uygula**, **Tekrar düzenle**, **Başka fotoğraf seç** vardır. Dokunma seçimi sayısal gösterim üzerinden yuvarlanmaz. Fotoğrafta/köşede başlayan hareket sayfa kaydırmasına kaptırılmaz; yavaş çapraz sürükleme de test edilir. Çoklu dokunuş aynı anda alanı değiştirmez.

Kırpma koordinatları küçültülmüş OCR dosyasına değil, yönlendirilmiş orijinale uygulanır. Tam çözünürlüklü döndürülmüş kopya oluşturulmadan seçili bölge sınırlı canvas’a çizilir. Sonraki hafif eğiklik düzeltmesi `ceil(w*cos+h*sin)` / `ceil(h*cos+w*sin)` sınırlarını ve 24 px beyaz çerçeveyi kullanır; köşeler kesilmez. Çerçeve dahil uzun kenar en fazla 2400 px, tek görüntü en fazla 6 milyon piksel (2400 kare sınırı fiilen 5.76 MP). Küçük resimler en fazla iki kat büyütülür; OCR’ye verilen **aynı PNG baytları** ekranda önizlenir.

Genişleyen beyaz köşeler açık renkli fotoğrafta motorun renk eşiklemesini şaşırtabildiği için, soluk baskıda yerel ortalamaya dayalı siyah-beyaz önizleme uygulanır: 4×4 blok integral görüntüsü, yaklaşık 100 px komşuluk, soluk baskıda ortalamadan %25, koyu baskıda %12 (her ikisinde en az 8 ton) koyu pikseller. Eğiklik düzeltmesi gerektirmeyen, siyah noktası 16’dan koyu görüntüler ile 220’den açık görüntülerin mevcut renkli işlenişi korunur. Bu görüntü dönüşümü **ham OCR metnini düzeltmez**, kumaş dokusunu kesin ayırdığını iddia etmez. Kullanıcı sonucu önizler; yetersizse yeniden kırpar/çeker veya elle düzeltir. Model güven eşiği, yüzde/elyaf filtresi, parser ve draft mantığı gevşetilmedi.

Giriş sınırları 20 MiB / 24 MP; ayrıca kaynak kenarı en fazla 32768 px, her kenar en az 32 px. Kontroller decode öncesinde ve sonrasında yapılır. Crop her iki yönde en az 32 kaynak pikseli ve en fazla 40:1 oran ister. Geçersiz alan Türkçe hata verir, önceki fotoğrafı değiştirmez. Görüntü işleri sıraya alınır; sahip olunan canvas’lar ve geçici eşikleme tamponları için 12 milyon RGBA piksel eşdeğeri (~48 MB) bütçe kontrolü vardır. Orijinalin decode belleği (24 MP’ye kadar), PNG/thumbnail, Flutter ve OCR worker belleği buna **eklenir**; bu sayı toplam uygulama belleği değildir. Eski kaynak/önizleme URL’leri referansları bittikten sonra iptal edilir, canvas boyutları sıfırlanır; ekrandan çıkan görüntüler Flutter decoded-image cache’inden de çıkarılır.

Her düzenleme/seçim yeni oturum revizyonu oluşturur. Yeni fotoğraf veya uygulanan crop eski OCR’yi ve kaynak onayını geçersiz kılar; **elle düzeltilmiş ham metin, yüzdeler ve elyaf satırları korunur**. Yeni OCR metninin yerini alması ayrıca sorulur; yeni metnin draft’a uygulanması da mevcut kullanıcı değişiklikleri için mevcut onay akışını kullanır. Geç kalan OCR/crop sonucu, yeni fotoğrafı veya manuel metni ezemez. İptal/geri/blur sırasında uygulanmamış düzenleme bırakılır; son uygulanmış fotoğraf kalır. Tarama oturumundan çıkış, başka fotoğraf ve sayfa kapanışı kaynakları temizler. BFCache’te kalmış sayfa, aktif oturumun fotoğrafını bellekte tutabilir.

**Native Android/iOS kırpma bu görevde desteklenmiyor.** Düzenleme düğmeleri yalnız Web kaynak metadatası varsa görünür; native fotoğraf seçme ve ML Kit akışı devam eder. Android APK derlemesi bu ayrımı doğrular; fiziksel cihaz/kamera/iOS derlemesi bu ortamda yapılmadı.

## W2 test kanıtı ve tekrar çalıştırma

Başlangıç `87b1de1…`: **104 Flutter + 11 JS testi PASS**. W2 yerel regresyon sonucu **122 Flutter + 16 JS PASS**; eski testler ve beklentileri korundu. Önce yeni test, köşeye yakın 9° kaynakta gerçek Tesseract.js çıktısını **`0% PAMUK / 0% POLYESTER`** olarak kaydetti; dört köşe işareti de kayboldu. Düzeltilmiş 9° ve 12° örneklerinde gerçek çıktı **`80% PAMUK / 20% POLYESTER`**, dört köşe ayrı ayrı korunuyor. Oranlar yalnız OCR çıktısı üzerinde kontrol edilir; sayım tek başına başarı sayılmaz.

`node scripts/web_ocr_smoke.cjs http://127.0.0.1:8082/etiket/` mevcut bütün testleri ve şu W2 modüllerini birlikte çalıştırır:

- `web_ocr_edge_regression.cjs`: kaynak 1200×600, 9°/12° köşe yazısı, her köşede piksel kontrolü, gerçek OCR oranları.
- `web_ocr_crop_smoke.cjs`: gerçek compiled Flutter UI; 360×800 / 390×844 / 430×844 / 1280×844. Dokunma ve fare ile köşe sürükleme, sayısal crop, reset, 270°/180°/90° dönüşler. Portre 1280×1800 ve yatay 2400×1600 dokulu/küçük/karanlık sentetik etiketler, tam kare ve crop çıktılarının raporu; OCR girdisi ile görünen önizlemenin SHA-256 eşitliği. Manuel düzeltme, iptal, yeniden okuma, zorunlu onay ve kaynak temizliği.
- `web_ocr_crop_safety.cjs`: kırpılmış boş/dokulu/yüzdesiz malzeme adı/`2026 COTTON` gerçek motorla `emptyText`; JPEG EXIF 3/6/8 ve aynalı 2 yönü, normalleştirilmiş kaynak boyutları ve gerçek 80/20 OCR. Fotoğraf/metin upload isteği yok.

Tam kare kötü yönlendirilmiş fotoğrafın başarısızlığı raporda açıkça kalır; crop sonrası sonuçla kıyaslanır. `crop-report.json`, `crop-safety-report.json`, `edge-report.json`, işlenmiş/source sentetik resimler ve ekran görüntüleri CI’ın `doku-web-ocr-evidence-<SHA>` artifact’ındadır. Mevcut model hatası/offline/iptal/izin/doku testleri çalışmaya devam eder. Flutter testleri klavye açık erişimi, çoklu dokunmayı, arka plana geçişte geç crop sonucunu, önceki onayın kaldırılmasını ve düzeltilmiş draft’ın korunmasını da kapsar. CI Android artifact’ı `doku-android-debug-<SHA>` gerçek telefona kurulabilir.

### Manuel Pages kontrolü (ancak ayrıca yayımlandıktan sonra)

1. Telefon tarayıcısında `/etiket/` aç; 360/390/430 dp ve masaüstünü dene. Ağ panelinde motor/model/core isteklerinin aynı `/etiket/ocr/` altında 200 olduğunu doğrula; fotoğraf/metin upload isteği olmamalı.
2. **Etiket tara → Fotoğraf çek/yükle → Fotoğrafı düzenle**. Etiketi köşelerle daralt; kenardaki bütün rakamları içeride ve biraz boşlukla bırak. Alanı taşı, sayısal değerleri klavye açıkken değiştir. Çok dar/sınır dışı alanda anlaşılır hata bekle.
3. Sağ/sol 90° dönüşleri ve sıfırlamayı dene. Uygula; önizlemede kenar harflerinin kaldığını, kumaş dokusunun azaldığını gözle kontrol et. Tekrar düzenle; orijinalin açıldığını doğrula. İptal/geri veya uygulamayı arka plana alma önceki uygulanmış önizlemeyi korumalı.
4. **Fotoğraftaki metni oku → Metni incele ve düzelt**. Yanlışları elle düzelt; geri dön, yeniden kırp/oku. Eski metin otomatik değişmemeli. Yüzdeleri düzenleyip onayladıktan sonra başka fotoğraf seç; önceki yüzdeler kalmalı, onay kaldırılmalı.
5. Boş/dokulu görüntü ve tarih/malzeme adı gibi etiketsiz fotoğrafları dene. Hata sonrası crop, başka fotoğraf, metin yapıştırma ve elle giriş kullanılabilir olmalı. Sonuçları fotoğrafla tek tek karşılaştırıp onaylamadan analize geçme.

**Sınır / #11 takibi:** Yalnız sentetik görüntüler mevcut; gerçek kullanıcı kıyafet fotoğraflarıyla benchmark BLOKLU (bu görev için paylaşılmış, kullanımı onaylı gerçek fotoğraf kümesi yok). Bu PR bir gerçek dünya başarı oranı veya fiziksel Android/iOS/Pages kamera başarısı iddia etmez. #11’deki gerçek fotoğraf benchmarkı ve cihaz/browser matrisi takip işi olarak kalır. Bu görev merge veya Pages deployment başlatmaz.
