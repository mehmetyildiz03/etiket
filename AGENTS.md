# Codex / geliştirme talimatları — Etiket (Doku)

Bu dosya, bu depoda çalışan kod asistanları için **kalıcı proje kurallarıdır**. Yeni görev talimatı ile çatışma olursa kullanıcıdan açıklama iste; güvenlik/veri bütünlüğü sınırlarını sessizce aşma.

## Ürün
- Etiket (çalışma adı: **Doku**), kıyafet etiketindeki elyaf bileşimini anlaşılır kılan **mobil öncelikli Flutter** uygulamasıdır.
- Öncelik Android, daha sonra iOS. GitHub Pages, telefon tarayıcısından tasarımı ve saf Dart özelliklerini denemeye yarayan **web önizlemesidir**; native mobil uygulamanın yerine geçmez.
- Türkçe kullanıcı arayüzünü, koyu yeşil `#254A3F` ve kırık beyaz `#F4F2EC` tasarımını ve mevcut ekran akışını koru. Değiştirmen gerekiyorsa görevin gerekçesini açıkla.
- İlk sürüm: üyelik gerekmez; ücretli API, arka uç servisi ve üretken yapay zekâ ekleme. Böyle bir ihtiyaç varsa önce gerekçelendir ve kullanıcı onayı iste.

## Doğruluk ve veri bütünlüğü (kritik)
- **Etikette yazan doğrulanmış elyaf oranı** ile **liflerden çıkarılmış genel konfor / nem / kalite tahmini** ayrı gösterilmeli. Etiketten kesin terletme, nefes alabilirlik, cilt güvenliği, alerji veya kalite puanı çıkarmamalısın.
- Belirsiz, okunamayan, eksik veya çelişkili yüzde/elyaf bilgilerini **uydurma, tahmin ederek tamamlayıp doğrulanmış gibi sunma veya sessizce düzeltme**.
- Dış kumaş, astar, dolgu gibi bileşenler ayrı kalmalı; her bileşenin yüzdeleri **kendi içinde** doğrulanmalı. Farklı bileşenlerin oranlarını birleştirme.
- Elyaf adı bilinmiyorsa kullanıcıya belirsizliği göster; kesinlikle keyfi bilinen bir elyafa eşleme. Kullanıcının düzeltmesini izinsiz tekrar eski ayrıştırma/OCR sonucuyla değiştirme.
- Satırların kimliğini, değişken sayıda elyafı, yinelenen farklı bölümleri ve elle düzenlenebilirliği koru.
- OCR gelecekte ayrı bir girdi katmanı olacak. Metin ayrıştırma ve kumaş karar mantığı UI/kamera kodundan mümkün olduğunca bağımsız, test edilebilir Dart modülleri olmalı.

## Çalışma biçimi
1. Kod yazmadan önce `README.md`, `docs/ROADMAP.md`, `docs/DEVELOPMENT.md` ve ilgili kod/testleri incele. Var olmayan dosyalara dayanma.
2. Görevin kabul kriterlerini belirle. Karmaşık/hatalı girdiler ve kullanıcı etkileşimleri için önce başarısızlığı ortaya koyan testler ekle; testleri çözüm için gevşetme.
3. Kapsamı dar tut. İlgisiz refactor, paket güncelleme, Android ayarı, tasarım değişikliği, büyük veri kaynağı veya yeni servisi aynı PR'a ekleme.
4. Hata olursa nedeni araştır, kapsamdaki hatayı düzelt ve ilgili kapıları yeniden çalıştır. Tek başarısızlıkta bırakma; ancak dış ağ/izin engelini kod başarısı gibi raporlama.
5. Hiçbir testi atlama, silme, beklentileri gevşetme veya uydurma başarı raporu verme.

## Doğrulama
Her kod PR'ında değişikliğe uygun testleri çalıştır ve sonucu açıkça raporla:
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Web etkileniyorsa `flutter build web --release --base-href=/etiket/` (gerekirse önce geçici web runner oluştur).
- Android etkileniyorsa `flutter build apk --debug`.
- GitHub Actions: `Flutter Android` ve `Doku mobile web preview` iş akışlarının ilgili PR başındaki **exact SHA** sonucunu kontrol et.
- Bulut ortamı HTTP 403 gibi nedenle çalışamıyorsa **BLOCKED** de; GitHub Actions sonuçlarını bulut ortamında çalıştırdığın testlerle karıştırma.
- Gerçek telefon testi, ekran görüntüsü, kamera/OCR veya iOS derlemesini **yapmadıysan yapıldı deme**.

Ayrıntılı kontrol listesi: `docs/QUALITY_GATES.md`.

## Git ve teslim
- Kural olarak `main` üzerinde doğrudan geliştirme yapma. Güncel `main`'den ayrı branch aç; var olan dosyaları ve geçmişi koru.
- Değişiklikleri PR olarak sun. Kullanıcı **22 Ekim 2026'da Doku için rutin test → inceleme → CI → merge/Pages yayınını ayrıca onay istemeden yapmamızı açıkça istedi**. Tam kalite kapıları başarılıysa güvenli ve geri alınabilir rutin değişiklikleri otomatik birleştirip yayımlayabilirsin. Test/CI başarısızsa dur ve düzelt; gizlilik, büyük altyapı maliyeti, yeni ücretli servis, geri döndürülemez veri işlemi veya ürün güvenliği riski söz konusuysa önce kullanıcı onayı iste. GitHub Pages `main` push'unda otomatik yayımlanır.
- Gizli anahtarları, token'ları, kişisel bilgileri, gerçek kullanıcı fotoğraflarını veya özel dokümanları repoya koyma. Pages kamuya açıktır.
- Final raporunda: kapsam, dosyalar, testlerin gerçek sonuçları, CI bağlantısı, varsa blokajlar, bilinen sınırlamalar ve PR bağlantısı. Başarı kriterleri tamamlanmadıysa açıkça belirt.
- Kullanıcının Doku 1.0 hedefi için açık **sürekli geliştirme ve rutin yayın yetkisi** bulunuyor; görev tamamlanınca yapılanları ve sıradaki işleri kaydet, güvenli bağımsız özelliklere yeni branch üzerinden devam edebilirsin. Gerçekte arka plan işlemi yürütülmüyorsa çalışmanın sürdüğü izlenimi verme.
