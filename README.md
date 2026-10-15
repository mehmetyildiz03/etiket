# Etiket (Doku) — Mobil Kumaş Rehberi

Etiket, kıyafetlerdeki elyaf bileşimlerini anlaşılır hale getirmeyi hedefleyen **mobil öncelikli** bir Flutter projesidir. "Doku" çalışma adı kesinleşmiş bir marka adı değildir.

## Durum
Android'de sistem kamerası veya galeriden alınan fotoğraf, cihaz üzerindeki Latin OCR ile okunabilir. Web'de fotoğraf yükleme ve destekleyen mobil tarayıcıda kamera seçimi, ücretsiz Tesseract.js Türkçe/İngilizce OCR ile tarayıcı içinde çalışır. İlk okuma için yaklaşık 9 MB motor/model indirmesi ve internet gerekir. Fotoğraf/metin sunucuya gönderilmez. Ham metin düzenlenir ve mevcut ayrıştırma/etiket doğrulama akışına aktarılır; OCR otomatik onay değildir. Manuel giriş, metin yapıştırma ve açıkça belirtilen demo kullanılabilir. Bakım sembolleri, hesap ve kalıcı kayıt yoktur. Tıbbi/alerji veya nesnel kumaş kalitesi iddiası üretmez.

## Windows + Android kurulumu
1. [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/mobile) ve Android Studio'yu kur; Android SDK/emülatörünü hazırla.
2. PowerShell'de `flutter doctor` çalıştır; Android lisansları sorulursa `flutter doctor --android-licenses` komutunu kullan.
3. Depoyu klonla: `git clone https://github.com/mehmetyildiz03/etiket.git`
4. `cd etiket`
5. Android platform dosyaları depoya dahildir; yeniden `flutter create .` çalıştırman gerekmez. Hedef Flutter stable sürümü `.flutter-version` dosyasında belirtilir. Kamera/OCR paketleri en az Flutter 3.44 / Dart 3.12 gerektirir; doğrulanan hedef Flutter 3.47.7'dir. Android 7.0 (API 24) veya sonrası gerekir.
6. `flutter pub get`, `flutter analyze`, `flutter test` ve ardından `flutter run` çalıştır.

iOS platformu daha sonra macOS + Xcode üzerinde oluşturulup test edilecek; iOS başarısı doğrulanmadı.

Linux bulut ortamı, ağ gereksinimleri ve doğrulama durumu için [geliştirme ortamı notları](docs/DEVELOPMENT.md).

## İlk akış
Ana sayfa → örnek tarama / elle giriş → oran doğrulama → kullanım amacı → gerekçeli sonuç. Birden çok kumaş bölümü (ör. dış kumaş/astar) ve sınırsız sayıda elyaf satırı desteklenir; her bölümün kendi toplamı %100 olmalıdır.

## Etiket metni ayrıştırma (F2-R1)

Ana sayfadaki **Etiket metnini yapıştır** seçeneği, TR/EN isimleri ve CO/PES/EL gibi açık kısaltmalarla yazılmış oranlar için düzenlenebilir bir öneri üretir. Dış kumaş, astar ve dolgu ayrı kalır; eksik veya belirsiz bilgiler tamamlanmaz. Ham metinle karşılaştırıp hatalı satırları düzeltmek ve **Etiketle karşılaştırdım ve doğruladım** seçeneğini işaretlemek gerekir. Mevcut düzeltmelerin yerini yeni metnin alması ayrıca açıkça seçilir.

Desteklenen biçimler ve sınırlamalar: [etiket ayrıştırma notları](docs/LABEL_PARSING.md). Ayrıştırma cihazda saf Dart koduyla yapılır. Fotoğraf/OCR akışı, paketler, dosya yaşam döngüsü ve Android telefon test talimatları: [mobil OCR notları](docs/MOBILE_OCR.md).

Web motor/model kurulumu, `/etiket/` statik adresi, gerçek tarayıcı testi ve çevrimdışı/kamera sınırları: [Web OCR notları](docs/WEB_OCR.md). Web build'den önce `npm ci --prefix tool/web_ocr --ignore-scripts --no-audit --no-fund` ve `node scripts/prepare_web_ocr.cjs` çalıştır; Actions bu adımları uygular.

Ham motor çıktısı, güven puanı ve kumaş etiketi kararı ayrı tutulur. “OCR'nin okuduğu ham metni göster” yalnız isteğe bağlı incelemedir; kumaş bileşimini doğrulamaz. Akış, test kanıtı ve sınırlar: [OCR tanıları](docs/OCR_DIAGNOSTICS.md), [doğruluk benchmark'ı](docs/OCR_BENCHMARK.md).

## Mühendislik ilkeleri
- **Etiket verisi ≠ performans ölçümü:** Terletme, nefes alabilirlik, kalite veya alerji kesin puanı üretmeyiz.
- OCR sonucunu kullanıcıya doğrulatırız; okunmayan oranları uydurmayız.
- Karmaşık taramalar başarısız olursa kullanıcı manuel girişe dönebilir.
- Veri öncelikle cihazda işlenir. Fotoğraf/analiz depolama daha sonra açık kullanıcı kontrolüyle eklenir.
- Yüksek kontrast ve rahat dokunmatik hedefler; Android ile ilk test.

## Yapı
- `lib/domain/` — elyaf bileşimleri, bölümler ve karar kuralları
- `lib/domain/label_parser.dart` — ham metin, ayrıştırma önerileri ve kaynak uyarıları
- `lib/domain/composition_draft.dart` — satır kimlikleri, kullanıcı düzeltmeleri ve doğrulama durumu
- `lib/main.dart` — mobil ekran akışı (ilk prototip)
- `test/` — alan modeli ve kural testleri
- `docs/ROADMAP.md` — sonraki geliştirme adımları

## Not
Bu proje bir prototiptir; yayıma hazır değildir. Veri tabanı henüz literatür taraması ve gerçek kumaş testleriyle doğrulanmamıştır.
