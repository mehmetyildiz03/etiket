# Mobil önizleme — GitHub Pages

Bu önizleme, Flutter mobil arayüzünü **telefonun tarayıcısında** denemek içindir; Android APK veya App Store sürümü değildir.

## Erişim
- Hedef URL: https://mehmetyildiz03.github.io/etiket/
- URL ancak ilk başarılı Pages deployment'ından sonra açılır.
- GitHub → Settings → Pages → Build and deployment → Source → **GitHub Actions** seçili olmalıdır.
- `main` dalına birleştirildikten sonra Actions → **Doku mobile web preview** iş akışını takip et.
- İş akışı, Pull Request üzerinde yalnızca web derleme kontrolü yapar; **main** üzerinde web sürümünü otomatik yayımlar.

## Bu sürümde çalışanlar
- Mobil ekrana uyarlanmış ana sayfa
- Demo etiket akışı ve elle bileşim girişi
- Elyaf ekleme/çıkarma ve kumaş bölümü ekleme/çıkarma
- Her bölüm için ayrı %100 doğrulaması
- Kullanım amacına göre temkinli kumaş yorumları

## Bu sürümde olmayanlar
- Gerçek kamera, fotoğraf yükleme ve OCR
- Telefon uygulaması olarak kurulum / native cihaz işlevleri
- Kaydetme veya hesap sistemi
- Gerçek dünya kumaş performansını ölçme

Uyarı: GitHub Pages kamuya açık bir önizlemedir; özel kişisel veriler veya fotoğraflar test verisi olarak kullanılmamalıdır.

## Teknik not
Web runner dosyaları yayımlama iş akışında `flutter create --platforms=web --project-name etiket .` ile **geçici olarak** üretilir; böylece Android proje dosyaları ve mevcut `lib/` korunur. `--base-href=/etiket/` depo alt yolunda asset adreslerinin doğru çalışmasını sağlar.

Yerelde test için:
```sh
flutter create --platforms=web --project-name etiket .
flutter pub get
flutter run -d chrome
```

## Kontrol listesi
1. PR build-web işi yeşil.
2. Pages Source = GitHub Actions.
3. PR main ile birleşti.
4. `main` üzerindeki deploy-pages işi yeşil.
5. Telefon tarayıcısında sayfa açılıyor ve örnek etiket akışı çalışıyor.
