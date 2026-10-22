# Doku D2 — Cihaz içi kıyafet geçmişi

Doku'nun **Geçmiş** ekranı yalnız kullanıcının sonuç ekranındaki **Kıyafeti kaydet** düğmesiyle oluşturduğu kayıtları listeler. Demo/örnek bileşimi ve onaylanmamış OCR otomatik olarak kaydedilmez.

## Veri ve güvenlik sözleşmesi

- Veri `shared_preferences` sürüm 2.5.6'nın **SharedPreferencesAsync** arayüzündedir. Android'de DataStore Preferences, iOS'ta NSUserDefaults, Web'de tarayıcı LocalStorage kullanılır. Sunucuya senkronizasyon yapılmaz.
- Tek anahtar: `doku.local_compositions.v1`, şema sürümü 1, **en fazla 100** kayıt. Kullanıcı adı (60 karakter), kaynağı `manual`/`label`, UTC oluşturma zamanı, bölüm/elyaf/yüzde kayıtları.
- Fotoğraf, EXIF, OCR'nin ham metni, model güven puanı, bakım işareti görüntüsü ve kullanıcıya ait kişisel dosya **kalıcı geçmişe yazılmaz**.
- Her bölüm kendi içinde tam %100 olmalıdır; oranlar tahmin edilmez. Import/OCR'den gelen bilgi kullanıcı tarafından açıkça doğrulanmadan kaydedilemez. Demo başlangıç bileşimi gerçek giysi kabul edilmez.
- Geçmişi görüntülemek fotoğrafı yeniden açmaz; kayıt salt okunur ayrıntı penceresiyle gösterilir.
- Kaydet/sil/tümünü sil sonrasında yazılan verinin yeniden okunmasıyla **best-effort doğrulama** yapılır. Aynı oturumun yazma işlemleri sıraya alınır.
- Bozuk, desteklenmeyen sürüm veya anlaşılmayan ek alan varsa **tüm yazma ve silme reddedilir**, kullanıcıya hata gösterilir. **Kayıt kurtarma/otomatik silme yapılmaz**.
- Depolama kota/izin kısıtlaması veya sekmeler arası aynı anda kayıt yarışı için **veritabanı ACID / gerçek disk fsync garantisi yok**. `shared_preferences` resmi belgeleri, `await setString` dönüşünden sonra disk kalıcılığının garanti olmadığını açıkça belirtir. Bu nedenle uygulama önemli kayıtlar için güvenli bir yedekleme çözümü yerine geçmez: https://pub.dev/packages/shared_preferences

## İş akışı ve silme

1. Kullanıcı gerçek etiketi okur veya elle içerik girip düzeltir. Mevcut onay ve her bölüm için %100 doğrulaması uygulanır.
2. Sonuçta **Kıyafeti kaydet** ile isteğe bağlı ad girer.
3. Depolama okuma/yazması başarısızsa başarı mesajı verilmez; geçmiş yeniden yüklenir veya hata durumu gösterilir.
4. **Geçmiş** sekmesinde kayıt görüntülenir. Kayıt ayrıntısı salt okunur. Tek kayıt veya tümünü silme ayrı onay gerektirir.
5. Ayarlar'daki **Tüm yerel geçmişi sil** aynı onaylı silme yolunu kullanır.
6. Farklı cihaz, özel mod veya tarayıcı veri temizliği sonrası geçmişin bulunmaması beklenen davranıştır.

## Testler ve sınırlar

`test/local_history_test.dart`: yeniden başlatma (yeni repository), farklı kumaş bölümleri, iki eşzamanlı kayıt, yanlış sürüm/bozuk JSON, yazma reddi ve geri kazanma, gizlilik alanları, tek sil/tüm sil.

`test/doku_history_flow_test.dart`: Flutter 390dp gerçek ana akış, manüel düzenleme, sonuçta Kaydet, yeni widget ağacından okuma, salt-okunur detay ve onaylı silme.

`flutter analyze`, `flutter test`, `flutter build web --release --base-href=/etiket/`, `flutter build apk --debug`, mevcut JS/OCR testleri ve exact SHA Web/Android CI zorunlu. Fiziksel iOS/Android cihaz test edilmeden yapıldı denmez.

Sıradaki olası geliştirme: çoklu tarayıcı sekmeleri ve cihaz kapatılmasını kapsayacak gerçek ACID kayıt çözümü; açık veri dışa aktarma/yedekleme. Bu özellikler D2 içinde yoktur.
