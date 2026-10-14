# Etiket (Doku) — Mobil Kumaş Rehberi

Etiket, kıyafetlerdeki elyaf bileşimlerini anlaşılır hale getirmeyi hedefleyen **mobil öncelikli** bir Flutter projesidir. "Doku" çalışma adı kesinleşmiş bir marka adı değildir.

## Durum
İlk aşama: mobil ekran akışı + kural tabanlı kumaş değerlendirmesi. **Gerçek kamera, OCR, bakım sembolleri ve kalıcı kayıt henüz entegre değildir.** İlk prototip örnek etiket ve elle giriş ile çalışır. Tıbbi/alerji veya nesnel kumaş kalitesi iddiası üretmez.

## Windows + Android kurulumu
1. [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/mobile) ve Android Studio'yu kur; Android SDK/emülatörünü hazırla.
2. PowerShell'de `flutter doctor` çalıştır; Android lisansları sorulursa `flutter doctor --android-licenses` komutunu kullan.
3. Depoyu klonla: `git clone https://github.com/mehmetyildiz03/etiket.git`
4. `cd etiket`
5. Depoya henüz eklenmemiş Flutter platform dosyalarını üret: `flutter create --platforms=android --project-name etiket .` (mevcut `lib/` dosyalarını ezmeden).
6. `flutter pub get`, `flutter test` ve ardından `flutter run` çalıştır.

iOS platformu daha sonra macOS + Xcode üzerinde oluşturulup test edilecek. Kodun yalnızca Flutter API'lerine dayanmasına dikkat ediyoruz.

## İlk akış
Ana sayfa → örnek tarama / elle giriş → oran doğrulama → kullanım amacı → gerekçeli sonuç. Birden çok kumaş bölümü (ör. dış kumaş/astar) ve sınırsız sayıda elyaf satırı desteklenir; her bölümün kendi toplamı %100 olmalıdır.

## Mühendislik ilkeleri
- **Etiket verisi ≠ performans ölçümü:** Terletme, nefes alabilirlik, kalite veya alerji kesin puanı üretmeyiz.
- OCR sonucunu kullanıcıya doğrulatırız; okunmayan oranları uydurmayız.
- Karmaşık taramalar başarısız olursa kullanıcı manuel girişe dönebilir.
- Veri öncelikle cihazda işlenir. Fotoğraf/analiz depolama daha sonra açık kullanıcı kontrolüyle eklenir.
- Yüksek kontrast ve rahat dokunmatik hedefler; Android ile ilk test.

## Yapı
- `lib/domain/` — elyaf bileşimleri, bölümler ve karar kuralları
- `lib/main.dart` — mobil ekran akışı (ilk prototip)
- `test/` — alan modeli ve kural testleri
- `docs/ROADMAP.md` — sonraki geliştirme adımları

## Not
Bu proje bir prototiptir; yayıma hazır değildir. Veri tabanı henüz literatür taraması ve gerçek kumaş testleriyle doğrulanmamıştır.
