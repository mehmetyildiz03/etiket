# F3-R1 — Mobil fotoğraf ve OCR

Başlangıç: `origin/main`, `0c817cda23a2c87b0c5205c97f681ae2ae3f8ae4`; 48/48 baseline testi geçti. Issue #5, `AGENTS.md`, kalite kapıları ve F2-R1 mimarisi incelendi. Oturum davranışları uygulanmadan önce 14 yeni sözleşme testi başarısız oldu; mevcut regresyon beklentileri değiştirilmedi.

## Akış

Android'de **Etiket tara → Fotoğraf çek / Galeriden seç → önizleme → Fotoğraftaki metni oku → Metni incele ve düzelt → Metni ayrıştır → Düzenleyicide incele → etiketle karşılaştırma/onay → analiz**.

Fotoğraf seçmek OCR'yi başlatmaz; OCR de ayrıştırma veya doğrulama yapmaz. Ham metin değiştirilebilir. Bozuk `7O%`, bilinmeyen elyaf ve eksik oranlar olduğu gibi korunur. F2-R1'in bölüm bazında %100 doğrulaması, kullanıcı onayı ve düzeltmeleri koruyan import sürümü kullanılır. Önceki ham metnin ve mevcut düzenlemelerin değiştirilmesi ayrı ayrı açıkça seçilir. DEMO akışı fotoğraf veya OCR kullanmadığını belirtir; manuel girişteki başlangıç değerleri örnek olarak işaretlidir.

360–430 dp için dikey, kaydırılabilir düzen, güvenli alan, 54 dp kaynak düğmeleri, fotoğraf önizlemesi, okunma durumu ve Türkçe hata/iptal mesajları vardır. Ham metin ekranı klavye açıkken kaydırılabilir. Web ve desktop'ta native OCR kapalıdır; metin yapıştırma, elle giriş ve açık DEMO korunur. Web OCR eklenmedi.

## Paket ve platform seçimi

- `image_picker 1.2.4`: sistem kamera intent'i ve sistem fotoğraf seçicisi. Android 13+ Photo Picker, önceki desteklenen Android sürümlerinde seçici fallback. Android için geniş `CAMERA`, `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` veya yazma izni eklenmedi. Kamera uygulamasındaki izin reddi Android'de intent iptali olarak da dönebilir; uygulama plugin'in bildirildiği ret/kısıtlama kodlarını ayrıca işler. iOS'ta `requestFullMetadata: false` gereksiz tam galeri metadata talebini önler.
- `google_mlkit_text_recognition 0.17.1`, `google_mlkit_commons` geçişli bağımlılığı: ML Kit Latin recognition. Android bağımlılığı **`com.google.mlkit:text-recognition:16.0.1`** modeli APK'ye dahil eder; bulut OCR veya çalışma anında model indirme API'si kullanılmaz. Türkçe/İngilizce etiket yazısı Latin kapsamındadır; diğer alfabeler için model eklenmedi.
- Paketler Flutter >=3.44 / Dart >=3.12 ister. Depo Flutter 3.47.7'ye sabitlenmiştir; Android API 24+, compile/target SDK 36 ve mevcut Gradle ayarları korunur. `pubspec.lock` uygulama bağımlılıklarını sabitler.
- Paketler iOS'u destekler; native adaptör iOS'a da uygundur. Bu depoda iOS runner yoktur. macOS'ta runner, minimum iOS 15.5, uygun Podfile/mimari ayarları ve `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` açıklamaları gerekir. iOS derlemesi, izinler ve gerçek iPhone akışı doğrulanmadı.

## Mimari ve veri yaşam döngüsü

`lib/scan/photo_scan.dart` kamera ve OCR arayüzlerini, Türkçe hata türlerini ve Flutter bağımsız tarama oturumunu içerir. F2-R1 parser/draft modülleri değiştirilmedi. UI'ye fake servis enjekte edilebilir. `scan_services.dart` conditional import ile web'in `dart:io`/native ML Kit katmanını kullanmasını önler.

Her seçim/OCR/metin değişikliği/iptal/ekrandan çıkış oturum sürümünü değiştirir. Eski sonuç aynı fotoğraf ve sürümle eşleşmedikçe uygulanmaz. Tekrar dokunmalar açık seçiciyi veya aynı OCR işini çoğaltmaz. Yeni fotoğraf seçmek eski OCR sonucunu geçersiz kılar. Arka plana alınan OCR iptal edilmiş sayılır; geri dönüşte kullanıcı tekrar okuyabilir. Sistem kamerayı/seçiciyi açmak ise beklenen arka plan geçişidir ve seçimi iptal etmez. Android activity yeniden oluşturulursa `retrieveLostData()` başlangıçta kontrol edilir; kurtarılan fotoğraf yalnızca önizlemeye gelir. Kullanıcı bu sırada başka ekrana geçtiyse kurtarılan eski fotoğraf uygulanmaz.

Seçici en fazla 2400×2400 boyut ve JPEG kalite 90 ister. Ayrıca 20 MiB / 24 milyon piksel sınırı, boş/bozuk dosya kontrolü ve sınırlı boyutta gerçek decode uygulanır. Fotoğraf uygulamanın özel geçici klasörüne kopyalanır; cache içindeki seçici kopyası kaldırılır, galerideki orijinal dosya silinmez. Özel kopya metin aktarma, yeni seçim, çıkış veya dispose ile temizlenir. Devam eden OCR'nin kullandığı dosyanın silinmesi iş bitene kadar ertelenir. Her native OCR işi kendi recognizer'ını `finally` içinde kapatır. Önceki süreçten kalan uygulamaya ait geçici klasörler başlangıçta temizlenir. OCR metni yalnızca aktif bellek/düzenleme oturumunda tutulur. Fotoğraf/metin loglanmaz, sunucuya gönderilmez veya depoya kaydedilmez.

Uygulama öldürüldüğünde eski düzenleme oturumu kalıcı olarak geri yüklenmez; kalıcı kayıt bu kapsamda yoktur. Sistem kamera/galeri uygulamalarının kendi veri saklama davranışı uygulamanın kontrolünde değildir.

## Android telefon testi ve APK

PR'ın **Flutter Android** Actions çalıştırmasında `doku-android-debug-<SHA>` artifact'i oluşur; saklama 14 gündür. GitHub'da oturum açıp Actions → ilgili commit'in başarılı çalıştırması → Artifacts üzerinden ZIP'i indir. İçindeki `app-debug.apk` geliştirme imzasıyla imzalıdır; herkese açık release veya mağaza paketi değildir. Android'de seçtiğin dosya yöneticisi için uygulama yükleme izni gerekebilir. İstersen bağlı cihazda `adb install -r app-debug.apk` kullan.

Gerçek telefon kabul kontrolü:

1. Kamera ile net TR/EN etiket çek; önizlemeyi kontrol edip OCR başlat. Ham metni düzelt; çoklu dış kumaş/astar oranlarını ayrı doğrula. Onay olmadan analiz düğmesi açılmamalı.
2. Galeriden seç; seçim/kamera iptali, izin/kısıtlama, net olmayan/boş fotoğraf ve tekrar denemeyi kontrol et. Uygun mesaj ve manuel alternatif görünmeli.
3. Hızlı çift dokun, OCR sırasında başka fotoğraf seç, geri dön veya uygulamayı arka plana al. Geç sonuç yeni fotoğrafı veya kullanıcı düzeltmesini değiştirmemeli. Android'in activity'yi sonlandırma durumunda seçim kurtarma davranışını kontrol et.
4. **Uçak modunda** yeni kurulmuş APK'de kamera ve yerel galeriden Latin OCR dene. Modelin paketlenmiş olması, gerçek cihazdaki çevrimdışı OCR'nin test edildiği anlamına gelmez.
5. 360–430 dp ekran, açık klavye, boş/bozuk yüzde, TR karakterler, geri navigasyonu ve veri onayını kontrol et. Gerçek fotoğrafı veya kişisel OCR metnini hata raporuna/depo/artifact'e ekleme.

## Kanıtın sınırı

Fake servis ve method channel testleri tarama sözleşmesini, API payload'unu, dosya temizliğini, race durumlarını ve UI'yi doğrular; gerçek kamera veya native ML Kit doğruluğunun kanıtı değildir. Kamera/galeri/OCR için gerçek Android telefonu veya emülatör sağlanmadı. Gerçek telefon, çevrimdışı OCR, iOS ve 50–100 etiketle doğruluk ölçümü henüz yapılmadı. Bu kontroller gerçek cihazda ayrıca kaydedilmelidir. `main` birleştirmesi veya Pages deployment'ı bu teslimin parçası değildir.
