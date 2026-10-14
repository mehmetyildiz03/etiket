# Etiket geliştirme ortamı

## Araçlar ve platform

- Hedef Flutter stable: **3.47.7** (`.flutter-version`). Resmi Flutter kaynak commit'i: `abaf9c523780a608bd46686fd5e53740a07077f8`.
- Android öncelikli; JDK 17 veya uyumlu daha yeni bir sürüm, Android SDK Platform 36 ve Build Tools 36.0.0.
- Android dosyaları aynı Flutter sürümünün resmi `app/android.tmpl` ve `app/android-kotlin.tmpl` şablonlarından oluşturuldu. Bulutta Dart SDK indirilemediği için `flutter create` çalıştırılmış gibi kabul edilmemelidir.
- Gradle 9.3.1, Android Gradle Plugin 9.1.0 ve Kotlin 2.4.0, resmi şablondaki sürümlerdir. Gradle wrapper JAR ve dağıtım sağlama toplamları Gradle'ın resmi yayınlarıyla doğrulandı.
- Uygulama kimliği geliştirme için `com.example.etiket`; mağaza yayını öncesinde kalıcı kimlik ve release imzası belirlenmelidir. Kamera/OCR bağımlılığı veya kamera izni eklenmedi.

## Çalıştırma

Flutter ve Android SDK kurulmuş, Android lisansları kabul edilmiş olmalıdır. `android/local.properties` makineye özeldir ve Git'e dahil edilmez. `flutter doctor -v` ile SDK ve cihaz durumunu kontrol et.

Depo kökünde:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d <android-cihaz-kimliği>
```

`flutter pub get` başarılı olduktan sonra üretilen `pubspec.lock` dosyasını uygulama deposuna ekle. Bu dosya ağ engeli nedeniyle bu değişiklikte üretilemedi; bağımlılıkların çözümlendiği varsayılmamalıdır.

Bulut makinesindeki yollar:

```sh
export PATH="/workspace/toolchains/flutter/bin:/workspace/toolchains/android-sdk/platform-tools:$PATH"
export ANDROID_HOME=/workspace/toolchains/android-sdk
export ANDROID_USER_HOME=/workspace/toolchains/android-user
export PUB_CACHE=/workspace/toolchains/pub-cache
export GRADLE_USER_HOME=/workspace/toolchains/gradle-cache
cd /workspace/etiket
```

Java/Gradle ortamın HTTPS proxy ayarını kendiliğinden kullanmazsa proxy host/port ayarlarını kullanıcıya özel `$GRADLE_USER_HOME/gradle.properties` dosyasında yapılandır. TLS doğrulamasını kapatma; proxy kimlik bilgilerini depoya yazma.

Her bulut görevi zaten izole bir ortamdır. Mevcut `/workspace/etiket` checkout'unu kullan; kullanıcı açıkça istemedikçe Git worktree oluşturma. Canlı süreçlerin ortam yayımlandığında korunacağını varsayma; her yeni görevde cihaz/emülatör bağlantısını ve `flutter run` işlemini yeniden başlat.

## Ağ ve mevcut doğrulama durumu

Flutter/Dart ve engine indirmeleri `storage.googleapis.com`, Dart paketleri `pub.dev`, Android SDK ve Google Maven `dl.google.com`, Gradle dağıtımları `services.gradle.org` ve yönlendirildiği GitHub yayın adreslerini gerektirir. Maven/Gradle plugin depoları ve GitHub erişimi de açık olmalıdır. Pull Request oluşturma ayrıca `api.github.com` erişimi gerektirir. Gizli anahtar gerektiren bir uygulama servisi yoktur.

14 Ekim 2026 bulut kurulumu:

| Kontrol | Sonuç |
| --- | --- |
| Flutter stable kaynaklarını klonlama | Başarılı; çalışır SDK kurulumu tamamlanmadı |
| Flutter/Dart SDK indirmesi | Proxy CONNECT aşamasında HTTP 403 |
| Android komut satırı araçları, Platform 36, Build Tools 36, platform-tools | Kuruldu; komut satırı aracı arşivinin resmi sağlama toplamı doğrulandı |
| `adb version` | Başarılı |
| `android/gradlew --version` | Proxy host/port ayarlarıyla başarılı; Gradle 9.3.1 |
| `flutter pub get` | Çıkış 56; Dart SDK indirmesinde durdu |
| `flutter analyze` | Çıkış 56; analiz başlamadı |
| `flutter test` | Çıkış 56; hiçbir test çalışmadı |
| Android APK derleme / cihazda çalıştırma | Flutter SDK engeli nedeniyle yapılmadı |
| iOS derleme | Yapılmadı; macOS ve Xcode gerektirir |

Kaydedilmiş ağ ayarında Flutter alan adı bulunsa da mevcut makinenin proxy'si 403 döndürdü. Gerekli alanların çalışan ortamda etkin olması sağlandıktan sonra yukarıdaki komutları yeniden çalıştır. Android SDK'nın kurulmuş olması uygulamanın derlendiğini veya mobil arayüzün çalıştığını kanıtlamaz.

Testler çoklu elyaf/dış kumaş/astar, her bölümde bağımsız %100 doğrulaması, geçersiz oranlar ve boş adlar, örnek analiz akışı, tema renkleri ve düzenleme sırasında satır kimliğinin korunmasını kapsar. Test dosyalarının eklenmesi, testlerin geçtiği anlamına gelmez.
