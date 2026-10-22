# Doku 1.0 — sekiz ekranlı mobil ürün hedefi ve uygulama sırası

**Tarih:** 22 Ekim 2026. **Tasarım dayanağı:** kullanıcıyla hazırlanan sekiz ekranlı bej / koyu yeşil mobil Doku görseli. Görsel bir **tasarım hedefidir**; şu anda bütün ekranların ve işlevlerin canlı uygulamada bulunduğu iddia edilmez.

## Kullanıcı deneyimi — hedef akış

1. **Oku / karşılama** — Doku logosu, gerçek örnek diye sunulmayan *örnek etiket görseli*, "Fotoğraf çek", "Galeriden seç", "Elle gir"; alt gezinme Oku/Geçmiş/Bilgi/Ayarlar; 360, 390, 430 dp.
2. **Etiket fotoğrafını düzenle** — seçilen **gerçek** fotoğraf görünür; kırp, 90° döndür, sıfırla, yeniden dene; boş önizleme olursa erişilebilir geri dönüş. Kaynak ve uygulanacak crop aynı.
3. **Metin okunuyor** — gösterilen adımlar gerçekten ölçülen durumla eşleşmeli; sahte yüzde veya sahte ilerleme çubuğu yok. OCR işlemi ve gizliliğe ilişkin doğru açıklama.
4. **Kumaş bileşimini doğrula / sonuç** — her bölüm ayrı, düzenlenebilir yüzde ve elyaf, %100 her bölüm için ayrı; açık etikete bakarak doğrulama. OCR'nin ürettiği hiçbir sayı sessizce düzeltilmez.
5. **Ana/alternatif OCR** — metin, motor puanı, kaynak ve karar ayrı; puan "doğru olma olasılığı" değildir; alternatif kendiliğinden asıl metni geçersiz kılmaz.
6. **Geçmiş** — yalnızca kullanıcı açıkça *Kaydet* dediği girdinin cihaz içinde kaydı; yeniden açma ve silme. OCR fotoğrafı ve kişisel metin varsayılan olarak kaydedilmez. Kaydetme eklenene kadar sahte tarihli örnek geçmiş gösterme.
7. **Elyaf bilgi kütüphanesi** — her elyaf için kaynaklı, temkinli açıklama (bilinen özellikler, elyaf yüzdesinden **ölçülemeyen** hava geçirgenliği, terleme, cilt toleransı, gerçek kullanım performansı).
8. **Ayarlar** — fotoğraf gizliliği, cihaz içi işlem, veri yönetimi ve silme, uygulama bilgisi; ayar düğmeleri gerçekte bir şey yapmalı, sahte kontrol kullanılmamalı.

## Kaynaklar ve ürüne etkileri

- **GINETEX / ISO 3758:2023:** 5 ayrı kategori: yıkama, ağartma, kurutma, ütü, profesyonel bakım; https://www.ginetex.net/gb/labelling/care-symbols.asp. Bakım işaretleri GINETEX marka/telif bağlamına tabi olabilir; görsellerini lisans kontrolü olmadan uygulamaya kopyalama. Metin olarak genel açıklamalar sunulabilir; gerçek etikette otomatik sembol saptaması doğrulanmadan "tespit edildi" yazma.
- **AB 1007/2011:** elyaf bileşiminin doğru etiketlenmesi şartları; bakım işaretleri ve menşe bilgisi farklı konular; https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A32011R1007 . Hukuki tavsiye değildir.
- **Laundry Lens** (https://apps.apple.com/tr/app/laundry-lens/id1513767864): kamera/ikon kütüphanesi; özellikle küçük yazıda odaklama ve yanlış simge risklerini tekrar etme.
- **How to Wash** (https://howtowash.app/): sonuçta talimatları kullanıcı dilinde kategorilere ayırma.
- **Save Your Wardrobe** (https://apps.apple.com/tr/app/save-your-wardrobe-organiser/id1485757044): kayıtlı giysi / onarım / bakım kavramı; ilk sürüm için üyelik veya ücretli ağ hizmeti ekleme.
- **Bilimsel sınır:** fiber içeriği tek başına nefes alabilirlik/konforu ölçmez. 2025 materyal araştırması, yapı/kütle/kalınlığın etkisini vurgular: https://pubmed.ncbi.nlm.nih.gov/40333549/ ve https://pubmed.ncbi.nlm.nih.gov/35591640/.

## Öncelik ve iş paketleri

- **D1 / şimdi**: Bej-yeşil tutarlı tasarım sistemi, karşılama görseli, mobil sekmeler, *gerçek* bilgi kütüphanesi/ayarlar, sonucu özetleyen düzen. Akış bozulmasın; test + CI; yayın.
- **D2**: Geçmişin yerel depolama modeli, açık kaydetme/silme, kalıcılık ve gizlilik testleri. İzinler, zorunlu onay ve başka cihaz/sunucu senkronizasyonu yok.
- **D3**: bakım sembolleri için **manuel işaretleme/kütüphane**, görsel telif/lisans kontrolü, etiket fotoğrafına dayanmayan bakım tavsiyelerinin etiket sonucu gibi gösterilmemesi.
- **D4**: iPhone Safari gerçek crop/photo testleri, OCR karakter/yüzde doğruluğu ve gerçek veriye dayalı CER/WER; #18 ve #21 kapatılana kadar başarı iddiası yok.
- **D5**: erişilebilirlik, uzun ekranlarda alt navigasyonun safe area/klavye durumu, İngilizce/TR varyasyonları, yerel geçmişin dışa aktarılmadan silinmesi, App Store hazırlığı.

## Ürün güvenlik kararları

- Sonuç ekranında kullanıcı tarafından onaylanmamış etiket bilgisi **asla** doğrulanmış gibi sunulmaz.
- Bakım sembolü yakalanmadıysa "Görüntüden sembol doğrulanmadı" yaz; *örnek/manuel işaretlemeyi* fotoğraf tanıması gibi gösterme.
- Kayıt özelliği gelene kadar geçmişte uydurulmuş kayıtlar üretme.
- Yalnız yüzdeden "terletir", "kesin su emer", "alerji yapmaz" vb. iddialara ve kesin skorlamaya izin verme.
- Fotoğraf, yüzdeler ve ham OCR metni özel veri gibi ele alınır; GitHub/Pages/CI'ye kullanıcı görseli eklenmez.
- Her teslim ayrı branch/PR, exact SHA testleri ve mobil ekran kontrolleriyle; mevcut kullanıcı talimatı gereği güvenli/rutin yayın için ek onay gerekmez, büyük mimari/geri döndürülemez değişiklik öncesi iste.

## Kabul ölçütleri — D1
- Flutter 360/390/430 genişliğinde karşılama, yönlendirme, bilgi ve gizlilik ekranları kaydırma / geri / klavye ile kullanılabilir.
- Alt navigasyonun bütün düğmeleri gerçek ekrana yönlendirir; bilgilendirme yapılmayan özellik için düzmece kayıt bulunmaz.
- Etiket tara, galeri ve manuel giriş geçmişte çalışan işlevlere bağlanır.
- Bütün mevcut Flutter/JS testleri çalışır; Web build, Android APK, exact-SHA CI ve Pages başarı.


## D1 uygulama ayrıntıları

Bu paket yalnız **UI/yerleşim**, gerçek bilgi kartları, geçmişin dürüst boş hali ve mevcut sonuç akışının daha okunur sunumunu ekler. Bilerek **kalıcı geçmiş verisi, sembol sınıflandırma, fotoğrafı uygulamaya gömme, otomatik yüzde onarma veya yeni OCR modeli eklemez**. Doku'nun hazırlanan mobil tasarımına yaklaşır ancak birebir fotogerçekçi illüstrasyon değildir; görseldeki 'örnek etiket' stilize ve açıkça örnektir.

Eksik kalan D2/D3 işlerinde kayıt ve bakım sembolü tespitini uygulamış gibi gösterme.
