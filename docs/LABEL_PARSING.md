# F2-R1 — Kumaş etiketi ayrıştırma

Başlangıç: güncel `origin/main`, `36efd851a2ef6c4b86251993052c74f99beb3eaf`.
Kaynak incelemesinde metin girişi/ayrıştırıcı yoktu; örnek tarama, manuel düzenleyici ve çoklu bölüm modeli vardı. `AGENTS.md`, kalite kapıları, README, yol haritası, geliştirme/Pages belgeleri ve mevcut testler incelendi. Kod değişikliklerinden önce baseline komutları ve yeni hata senaryoları için testler hazırlandı; SDK indirme engeli nedeniyle başarısızlık test runner içinde gözlemlenemedi.

## Davranış sözleşmesi

- `70% cotton`, `cotton 70 %`, `%70 Pamuk`, `CO70%`, `70 pct`, `yüzde 70`; çok satırlı girdi ve `;`, `|`, `/`, virgül ayraçları desteklenir.
- Ondalık yüzdeler virgül/noktayla, en fazla iki ondalık basamakla kabul edilir. Oranlar doldurulmaz veya geçerli hale gelmeleri için yuvarlanmaz. Her bölümün toplamı tam yüzde birlik birimlerle ayrı ayrı 10.000 (%100) olmalıdır.
- Açık TR/EN adları ve kısaltmalar tam sözlük eşleşmesiyle normalleştirilir: CO → Pamuk, PES/PET/PL → Polyester, EL/EA → Elastan, CV/VI → Viskon, PA → Poliamid vb. Sözlüğün tamamı `label_parser.dart` ve alias testlerinde bulunur.
- P, PE, rayon, bambu/bamboo ve Tencel gibi genel veya belirsiz ifadeler belirli bir elyafa tahmin yoluyla eşlenmez. Bilinmeyen sözcükler ve OCR benzeri `7O%` gibi bozulmalar kaynak metinleriyle birlikte saklanır.
- Dış kumaş/outer fabric/shell, astar/lining, dolgu/filling/padding ve ana kumaş/main fabric başlıkları tanınır. Tekrarlanan başlıklar birleştirilmez; aynı elyaf farklı bölümlerde ayrı tutulur. Numaralı başlıklar (`Shell 1:`) ayrı kimliklerini korur.
- Tanınmayan başlıklar açık uyarı üretir; kullanıcı bölüm adını kontrol edip düzenlemelidir. Eksik bölümler, yüzdeler, elyaf adları, aynı bölümde yinelenen elyaflar ve toplam uyuşmazlıkları doğrulamayı engeller.
- Yüzde işareti veya açık yüzde sözcüğü olmayan sayılar, bakım talimatları, marka/üretim bilgileri ve desteklenmeyen adlar bileşime sessizce dahil edilmez veya atılmaz. Böyle parçalar için elle düzeltme/silme istenir.
- Ham girdi ve her kaynak satır korunur. Öneri **Henüz doğrulanmadı** durumundadır; düzenleyiciye aktarmak doğrulama değildir. Kullanıcı düzeltmeleri sonrasında ayrıca etiketi kontrol ettiğini belirtmeden analize geçemez. Her değişiklik bu doğrulamayı kaldırır.
- Yeni ayrıştırma mevcut bileşimi değiştirmez. Düzeltme/önceki onay varsa değiştirme açıkça seçilir. Eski bir taslak sürümüne hazırlanmış öneri, değiştirme izni olsa bile reddedilir. Boş/çok uzun bir öneri mevcut veriyi silemez.

## Mimari

`label_parser.dart` Flutter bağımsız, deterministik ve salt girdiden öneri üreten bir modüldür. Kaynak aralıklarından türeyen kimlikler, ham yazım, isteğe bağlı elyaf/yüzde ve Türkçe uyarılar içerir. Öneri koleksiyonları değiştirilemez; motor doğrulanmış giysi üretmez.

`composition_draft.dart` düzenleme oturumunu yönetir. Satır kimlikleri ad/oran/indeks değişikliklerinden bağımsızdır. Taslak sürümü, kabul edilen ham kaynak, kullanıcı değişikliği ve kaynak doğrulama durumu burada tutulur. `verifiedGarment()` geçersiz veya doğrulanmamış içe aktarımı reddeder. Flutter yalnız bu işlemleri çağırır; daha sonra OCR aynı öneri katmanına ayrı bir girdi olarak bağlanabilir.

`FiberEntry.percent` ondalık oranları korumak için `num` oldu; toplam doğrulaması yüzde birlik birimler kullanır. Karar motorunun performans/konfor yorumları doğrulanmış etiket bilgisinden ayrı kalır. Yeni paket, API, arka uç, kamera veya OCR eklenmedi.

## Kalite kapıları ve sınırlamalar

Başlangıç ve değişiklik sonrası yerel kapılar ayrı ölçülür. Bu bulut makinesinde Flutter 3.47.7 kaynakları var, fakat Dart SDK indirmesi `storage.googleapis.com` için proxy CONNECT HTTP 403 ile engellendi. Yerel test, analiz veya derleme başarısı iddia edilmez.

Mevcut regresyon beklentileri silinmedi veya gevşetilmedi. Yeni testler alias/yüzde biçimleri, ondalık toplamlar, dış kumaş/astar/dolgu, tekrarlanan bölümler, bilinmeyen/eksik/bozuk/çelişkili kaynak, ham kanıt, eski öneri, kullanıcı düzeltmesi, küçük ekran, açık klavye, boş giriş, geri navigasyonu ve açık doğrulamayı kapsar. Test tanımları eklenmiş olması testlerin geçtiği anlamına gelmez.

Gerekli kapılar:

```sh
flutter pub get
flutter analyze
flutter test
flutter create --platforms=web --project-name etiket .
flutter build web --release --base-href=/etiket/
flutter build apk --debug
```

Web runner üretimi geçicidir; kaynak, manifest veya mevcut testlerin üzerine yazılmamalıdır. Mevcut `Flutter Android` ve `Doku mobile web preview` iş akışları değiştirilmedi. PR'daki exact SHA için ikisinin de başarılı sonucu görülmeden F2-R1 bütün kalite kapıları tamamlanmış sayılmaz. GitHub API (`api.github.com`) erişimi bu ortamda engelliyse PR oluşturma ve exact SHA CI doğrulaması **BLOCKED** olarak raporlanır.

Gerçek telefon testi, ekran görüntüsü, kamera/OCR ve iOS derlemesi yapılmadı. GitHub Pages'e yayımlama yapılmaz; mevcut main sürümü korunur. Birleştirme/yayımlama ayrı kullanıcı kararıdır.
