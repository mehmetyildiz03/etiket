# Etiket — kalite kapıları ve görev şablonu

## Bir özelliğin tamamlanma kriterleri
1. **Önce kanıt:** Başlangıç davranışı, değiştirilecek sınır ve başarısız örnekler kaydedilmiş olmalı.
2. **Alan testi:** Çoklu elyaf, birden fazla kumaş bölümü, yüzde toplamı, eksik/bozuk/tanınmayan veri ve elle düzeltme etkileniyorsa kapsanmalı.
3. **Mobil akış:** Özellik UI içeriyorsa küçük ekranı, geri navigasyonu, klavye/açık formu, boş girişleri ve kullanıcıya gösterilen hata mesajlarını test et.
4. **Regresyon:** Mevcut `test/fabric_test.dart`, `test/widget_test.dart` ve diğer testler çalışmaya devam etmeli. Önceki kapsamı silerek veya test beklentisini gevşeterek başarı sağlanmaz.
5. **Yerel doğrulama:** `flutter pub get`, `flutter analyze`, `flutter test`. Web değişiyorsa web build, Android değişiyorsa debug APK build.
6. **PR bazlı CI:** GitHub Actions'daki `Flutter Android` ve `Doku mobile web preview` ilgili PR commit SHA'sı için yeşil olmalı; farklı SHA'ya ait yeşil durum kanıt değildir.
7. **Yayımlama ayrı karar:** Kod başarıyla derlenmiş olması gerçek Android telefonda denenmiş veya Pages'e yayımlanmış olduğu anlamına gelmez. PR kullanıcı onayı olmadan birleştirilmez.

## Etiket ayrıştırma için özel kabul kriterleri (sıradaki özellik)
- Yüzdelerin elyaf adından önce/sonra gelmesi, çok satırlı girdi ve TR/EN isim/kısaltmalar.
- Bilinen bölümler (ör. dış kumaş, astar) birbirinden ayrılır; her bölüm kendi içinde %100 kontrolünden geçer.
- Aynı elyafın ayrı bölümlerde bulunması veri kaybına veya yanlış toplama neden olmaz.
- Tanınmayan elyaf, belirsiz kısaltma, birden çok eşleşme, çatışan değerler ve OCR benzeri bozulmalar sessizce 'geçerli sonuç' olarak kabul edilmez.
- Bozuk/eksik yüzdeler otomatik doldurulmaz; kullanıcı düzeltmesi istenir.
- Ham girdi ve kullanıcıya sunulan ayrıştırılmış veriler gerektiğinde açıklanabilir/karşılaştırılabilir olmalı.
- Kullanıcının kabul edip elle değiştirdiği bileşim, daha eski bir ayrıştırma sonucuyla ezilmemeli.
- Pure Dart ayrıştırma motoru Flutter widget'larına veya platform OCR paketlerine bağımlı olmamalı.
- Web/Android kod paylaşımı korunmalı. Gerçek kamera ve OCR entegrasyonu **ayrı görev**.

## Görev tanımı için kısa şablon
- **Hedef:** Kullanıcı bu görev sonrasında ne yapabilecek?
- **Kapsam:** Değişmesi gereken modüller ve açıkça dışarıda kalan işler
- **Başlangıç kanıtı:** Kaynak branch/SHA, çalışan testler ve hata senaryosu
- **Kabul kriterleri:** Normal, sınır ve hata senaryolarında beklenen davranış
- **Kalite kapıları:** Test/analiz/build/CI; gerçek cihaz testini ayrı belirt
- **Teslim:** Ayrı branch, PR, exact SHA, Türkçe rapor, merge/deploy yok

Bu belge varsayımsal geçmiş test sayıları üretmez; yeni görevde gerçek baseline yeniden ölçülmelidir.
