# Etiket — Yol haritası

## Milestone 1 — Prototip (bu commit)
- [x] Flutter uygulama kaynakları ve Android hazırlık yönergeleri
- [x] Koyu yeşil/kırık beyaz mobil tema
- [x] Örnek tarama (kamera simülasyonu), manuel bileşim düzenleme
- [x] Çoklu kumaş bölümü ve dinamik elyaf satırı
- [x] Her bölümde %100 doğrulaması
- [x] Açıklamalı, temkinli kural motoru
- [x] Alan modeli için temel unit test
- [ ] Windows makinede `flutter doctor`, `flutter test` ve gerçek Android çalıştırması

## Milestone 2 — Gerçek fotoğraf
- [ ] Android kamerayı açma ve galeriden seçme
- [ ] ML Kit metin okuma; Türkçe/İngilizce ve CO/PES/EL kısaltma eşlemeleri
- [ ] Değişken etiket biçimleri, dış kumaş/astar ayrıştırma
- [ ] Belirsiz OCR okuması için düzeltme ekranı
- [ ] 50–100 etiketle doğruluk ölçümü (karakter, elyaf ve yüzde bazında)
- [ ] İzin reddi, silik fotoğraf, % toplamı uyuşmazlığı, çevrimdışı testleri

## Milestone 3 — Kullanıma hazırlık
- [ ] Bilimsel kaynaklarla elyaf veri tabanı ve uzman gözden geçirme
- [ ] Yerel kayıtlar, silme ve gizlilik kontrolleri
- [ ] Erişilebilirlik; küçük ekran, dinamik yazı, screen reader
- [ ] iOS/macOS derleme ve App Store gereksinimleri
- [ ] Bakım sembolleri ve marka/lisans hukuku incelemesi

## Uygulama ilkeleri
1. Etiket bileşimi kesin olabilir; performans iddiası çoğu zaman tahmindir.
2. Doğrulanmamış oranların hiçbirini otomatik tamamlamayız.
3. Tüm elyaf yüzdeleri *her bölüm için* %100 olmalıdır.
4. Fotoğrafın yerel işlenmesi tercih edilir; kullanıcı izni ve silme seçeneği tasarlanır.
5. Kullanıcı hesabı ve abonelik ilk sürüm için gerekli değildir.
