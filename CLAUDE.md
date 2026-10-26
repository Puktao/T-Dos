# F-Do’s – Proje rehberi (Claude Code için)

Otel içi iş atama uygulaması. Resepsiyon, Kat Hizmetleri, Teknik, Satınalma, Mutfak, Servis ve Muhasebe arasında arıza, temizlik, müşteri, satınalma ve mutfak taleplerini açma, atama ve takip etme.
Telefonda ana ekrana eklenen bir PWA olarak çalışır. Bu dosya, claude.ai'daki tasarım konuşmasında verilen kararların özetidir.

## Kullanıcıyla çalışma
- Dil: **Türkçe**. Arayüz metinleri de Türkçe.
- Kullanıcı danışman tavrı istiyor: hata, risk ya da yanlış varsayım varsa **ilk cümlede** söyle. Övgü ve dolgu cümlesi kullanma.
- Önemli iddiaları etiketle: **[Kesin]**, **[Muhtemel]**, **[Tahmin]**. Kullanıcı itiraz ederse yeni bilgi yoksa pozisyonunu koru.
- Kullanıcı geliştirici değil. Teknik adımları tıklama düzeyinde anlat, mümkünse işi kendin yap.
- Tasarım isteklerini birebir uygula. Belirsizlikte kendi yorumunu bir cümleyle söyle ve devam et.

## Mimari
- **Tek dosya:** `index.html` (CSS ve JS satır içinde). Kütüphane olarak yalnızca `@supabase/supabase-js` UMD sürümü (jsDelivr, sabit sürüm `2.117.3`, global `supabase`). Uygulama içindeki istemci değişkeninin adı `sb`.
- **Bağlantı:** `supabase-config.js` → `window.FDOS_SUPABASE = {url, anonKey}`. Yalnızca anon / publishable anahtar. **service_role / secret anahtar asla depoya girmez.**
- **Veritabanı:** `schema.sql` (birden fazla çalıştırılabilir)
  - Tablo `public.fdos_tasks(id text pk, data jsonb, status gen., done_at gen. bigint, created_at, updated_at)`.
  - RLS: yalnızca `authenticated`. Okuma ve güncelleme `fdos_can_see(data)` ile sınırlı (atanan departman, işi açan, yönetici); ekleme yalnızca profili olan kullanıcı ve yalnızca kendi adına (`createdUid = auth.uid()`, `schema.sql` 12. bölüm; silinen kullanıcının açık kalan oturumu iş açamaz). Silme `fdos_can_delete(data)`: işi açan kişi (onaylanmamış işte) ve yönetici. `anon` erişimi yok.
  - Tetikleyici `fdos_tasks_guard` (`schema.sql` 13. bölüm): eklemede `createdBy`/`createdDept`/`createdUid` profilden yazılır; güncellemede bu üç alan değiştirilemez; kontrolü onaylanmış iş (`verified = true`) yalnızca onay kaldırılarak (Yeniden aç) değiştirilebilir. `auth.uid()` boşsa (Supabase paneli) kural uygulanmaz.
- `fdos_patch_task(p_id, p_patch jsonb)` → `data = data || p_patch`, **boolean döner** (iş görünmüyorsa `false`; uygulama "başka departmana aktarılmış ya da silinmiş" uyarısı verir). Üst düzey alanları birleştirir; güncellemeler bununla yapılır. Dönüş türü değiştiği için 3. bölüm fonksiyonu önce `drop` eder.
  - Realtime: tablo `supabase_realtime` yayınında.
- **Veri akışı:** Açık işler (`status in (yeni,devam,beklemede)`) ve son 30 günde tamamlananlar (`done_at >= now-30g`) çekilir. Realtime kanalı `fdos-tasks` ile değişiklikler uygulanır. Kanal yeniden bağlandığında, sekme görünür olduğunda, internet geri geldiğinde ve ekran açıkken 5 dakikada bir `refetch()` çalışır. Yazmalar önce yerelde uygulanır (`applyRow(..., true)`), hata olursa `refetch()` ile geri alınır.
- **Hızlı açılış:** Son görülen işler, profil (`me`) ve listeler cihazda `localStorage["fdos.snap"]` içinde saklanır (`saveSnap`, `loadSnap`). Açılışta önce bunlar gösterilir, sunucu verisi gelince yerine geçer. Oturum kapanınca ya da başka hesapla girilince silinir. Oturum doğrulanana kadar (`authReady = false`) yazma yapılmaz, "Bağlanıyor…" uyarısı çıkar.
- **Giriş:** Supabase Auth, e-posta ve şifre. Kayıt (sign-up) kapalı, kullanıcıları yönetici panelden ekler. "Şifremi unuttum" → `resetPasswordForEmail` → `PASSWORD_RECOVERY` olayında "Yeni şifre" ekranı açılır.
- **Kimlik:** Ad, departman ve rol `public.fdos_profiles` tablosundan gelir (hesaba bağlı). Personel kendi kaydını değiştiremez; yönetici atar. Kayıtlarda kullanıcı id'si değil ad yazılır (`createdBy`, `log.by`). Profil yüklenene kadar (`me = null`) hiçbir iş gösterilmez ve değiştirilemez ("İşler yükleniyor"). Eski "cihazda ad/departman seç" düzeni (`localStorage["oia.me"]`) ve salt okunur mod kaldırıldı.
- **Yönetici (admin):** Yalnızca `tuncer@feronya.com` (ad "Tuncer", departman `yonetici` = "Yönetici", rozet YÖN). Diğer herkes personeldir. Uygulamada **"Yetki" seçimi yoktur**; rol veritabanında e-postaya göre zorlanır (`fdos_profiles_guard` tetikleyicisi, `schema.sql` 9. bölüm). "Yönetici" departmanı başkasına atanamaz, iş formunda ve Rapor departman tablosunda görünmez (türü yok). Hesabım → **Kullanıcılar**: önce kayıtlı kullanıcılar listesi gelir (satır başına Kaydet düğmesi yok). Satırı **sola kaydırınca** sağda **Düzenle** ve **Sil** çıkar (satıra dokunmak da açar). Sağ üstteki **+** yeni kullanıcı formunu açar (Ad, E-posta, Geçici şifre, Departman → Kaydet). Düzenle aynı formu bilgilerle açar (Ad, Departman → **Güncelle**; e-posta ve şifre değiştirilmez). Sil iki aşamalı (Sil → Eminim), `fdos_admin_delete_user` ile; yönetici ve kendi hesabı silinemez. Rapor'da yalnızca yöneticiye görünen **Kişiler** tablosu var.
- **Kullanıcı ekleme:** `fdos_admin_create_user(p_email, p_password, p_name, p_dept, p_role)` SQL fonksiyonu (security definer, yalnızca yönetici). `auth.users` ve `auth.identities` satırlarını doğrudan ekler, kullanıcı onaylı açılır. Bu Supabase'in iç tablolarına yazdığı için resmî yol değildir; Supabase Auth şeması değişirse güncellenmesi gerekebilir. Edge Function kullanılmıyor (kullanıcı panelden yükleyemedi). Profil satırı `auth.users` tetikleyicisiyle kendiliğinden oluşur.
- **PWA:** `manifest.webmanifest`, `sw.js` (aynı köken için önce ağ, ağ 1,5 sn içinde yanıt vermezse önbellek; CDN için önce önbellek), `icons/`. **Her yayında `sw.js` içindeki `CACHE` sürümünü artır.**
- **Yayın:** GitHub Pages, `main` dalının kökü. `.nojekyll` var.

## İş kaydı (`data` alanı)
`type, cat, dept, room, desc, items[{id,text,done,by?,at?}], ooo, guest, status, createdAt, updatedAt, doneAt, doneBy, verified, verifiedBy, createdBy, createdDept, createdUid, log[{t,by,msg}]` (`log` en fazla 40 kayıt tutar)
- **Aciliyet (`prio`) ve son tarih (`dueAt`) 26/10/26 kaldırıldı** (kullanıcı kararı): formda, kartta, detayda, filtrede, Rapor'da yok; veritabanından da silindi (`schema.sql` 15. bölüm). Eski geçmiş (log) yazılarında "Acil, son tarih …" kalabilir.
- Renkler: **açık iş mavi** (`.card.open`, `--sureli` tokenları), **tamamlanan iş yeşil** (`.card.done`, `--ok` tokenları). Kırmızı yalnızca uyarı, silme ve SATIŞA KAPALI için.
- `status`: `yeni` · `beklemede` · `dnd` ("DND Kartlı", yalnızca oda numarası olan işte seçilebilir; oda alana çevrilirse Güncelle'de `yeni`ye döner) → `tamam`. **"Devam ediyor" (`devam`) 26/10/26 kaldırıldı**; eski kayıtlar `schema.sql` 16. bölümle `yeni` yapılır (uygulama eski `devam` kaydı görürse etiketini gösterir, seçenek olarak sunmaz). Açık durumlar: `yeni, beklemede, dnd` (+ eski `devam`). Resepsiyon "Kontrol edildi" der (`verified`), bu durumda `ooo` (satışa kapalı) kalkar.
- Satınalma ve Muhasebe işlerinde `room` boştur (`alan_gerekli = false`), kartta "TALEP / SAT" ya da "TALEP / MUH" görünür.

## Listeler (Supabase tabloları)
- `fdos_departmanlar(kod, ad, kisa_ad, rozet, alan_gerekli, sira, aktif)`, `fdos_turler(kod, ad, departman, sira, aktif)`, `fdos_kategoriler(tur, ad, sira, aktif)`, `fdos_alanlar(ad, sira, aktif)`. Kullanıcı bunları Supabase Table Editor'dan düzenler.
- Uygulama girişte ve `refetch()` sırasında `loadLists()` ile okur, `DEPTS`/`TYPES`/`AREAS` nesnelerinin içini değiştirir. Tablolar yoksa ya da boşsa aşağıdaki sabitler kullanılır.
- `aktif = false` olan kayıt seçim listelerinde görünmez, eski işlerde adı görünmeye devam eder. Silme yerine pasif yapılır; `kod` değiştirilmez (işlerde kodla kayıtlı).
- `alan_gerekli = false` olan departmanda (Satınalma) iş açarken alan/oda sorulmaz. Eskiden koddaki `"satinalma"` kontrolüydü, artık `DEPTS[k].noArea`.
- Okuma: giriş yapan herkes. Yazma: yalnızca yönetici (`fdos_is_admin()`); Supabase paneli bu kurala takılmaz.

## Sabitler (index.html içinde, tablolar yoksa yedek)
- `DEPTS`: teknik, kat (Kat Hizmetleri), resepsiyon, satinalma, mutfak, servis (rozet SRV), muhasebe (rozet MUH, alan sorulmaz), yonetici (yalnızca Tuncer).
- `TYPES` (her tür tek departmana bağlı): Arıza→teknik · Temizlik Talebi→kat · Müşteri Talebi→kat · Resepsiyon Talebi→resepsiyon · Satınalma Talebi→satinalma · Mutfak Talebi→mutfak · Servis Talebi→servis · Muhasebe Talebi→muhasebe (Fatura / hesap düzeltme, Ödeme, Avans / masraf, Diğer). "Oda servisi" (yemek hazırlığı) Mutfak'ta; Servis'te "Oda servisi teslim / tepsi toplama" var. Kategoriler türün içinde tanımlı.
- `AREAS`: Lobi, Restoran, Bar, Mutfak, Toplantı Odası, Koridor. Bunlara ek olarak "Oda No" seçeneği var; seçilince yanındaki oda numarası alanı açılır.

## Kullanıcının kesinleştirdiği arayüz kararları
1. Uygulama adı **F-Do’s**. Logo: lacivert zemin, beyaz `F-Do`, sarı tire, üstte küçük sarı `’s`; "Do" F’den küçük, altında yalnızca "Do" boyunca düz sarı çizgi, çizginin alt kenarı F’nin alt ucuyla aynı hizada (Big Shoulders Display 800). Uygulama ikonu, üst köşedeki logo ve giriş ekranındaki logo aynı çizimdir: `index.html` içindeki `#fdosLogo` SVG sembolü ve `icons/*.png`. Yazı tipi ya da renk değiştirilmez.
2. Alt tablar: **Anasayfa · Yapılacaklar · Tamamlananlar · Rapor**. Uygulama **her açılışta Anasayfa** ile başlar (adres çubuğundaki #sekme dikkate alınmaz); her girişte (hangi kullanıcı olursa olsun) ve arka planda 10 saniyeden uzun kalıp geri gelinince de Anasayfa'ya döner (açık iş/kullanıcı formu varsa dokunulmaz). Üst çubukta logonun yanında sekme adı yazmaz (başlık yalnızca ekran okuyucu için, `sr-only`).
3. **Anasayfa** sırası:
   - "Yeni işler" (açık gri kutu, solda koyu çentik; durumu Yeni olan işler, dokununca Yapılacaklar "Durum: Yeni" filtresiyle açılır) ve "Bitmemiş işler" (solda açık gri çentik, departman dağılımı) adlı iki büyük kutu.
   - "Açık işler" listesi: tüm açık işler, **en eski açılan en üstte**, en fazla 12 iş, fazlası için "Tümünü gör".
4. **Tarih biçimi her yerde `gg/aa/yy ss:dd`** (ör. 23/10/26 14:30; `fmt()`); "Bugün / Yarın / Dün" yazılmaz. Açık işin kartında **"Açılış: …"**, tamamlanmış işte **"Bitti …"** yazar. Kalan süre / gecikme yazısı hiçbir yerde yazılmaz.
5. **Liste ekranları** (Yapılacaklar ve Tamamlananlar):
   - Kartlar ve soldaki çentik: açık iş mavi, tamamlanan iş yeşil. **Açık iş kartlarının sağ alt köşesinde küçük "Bildiren: Ad"** yazar (Anasayfa ve Yapılacaklar; Tamamlananlar'da yok). Yapılacaklar **en eski açılan önce**, Tamamlananlar en son biten önce sıralanır.
   - **Sola kaydırarak silme** (tüm listeler: Anasayfa, Yapılacaklar, Tamamlananlar): kartı sola kaydırınca sağda kırmızı **Sil** çıkar, iki aşamalı (Sil → Eminim). İşi açan kişi kendi işlerini (kontrolü onaylanmamışsa), yönetici her işi siler (`canDelete(t)`; veritabanında `fdos_can_delete(data)`, `schema.sql` 11. bölüm).
   - Üstte arama alanı, sağında Filtre düğmesi.
   - Filtre panelinde **yalnızca Durum** var (Yeni / Beklemede / DND Kartlı). Tamamlananlar'da Durum = Kontrol bekleyen / edilen.
   - Panelde "Sıfırla" ve "… işi göster" düğmeleri yok; seçim anında uygulanır, panel ✕ ya da dışına dokunarak kapanır.
   - Açık filtreler arama alanının altında kaldırılabilir etiket olarak görünür.
6. **"Yapılacak İş" formu** sırası:
   - [Sorumlu departman | Bildirim türü] yan yana. Tür listesi seçilen departmana göre daralır.
   - Alan açılır listesi ve sağında oda no alanı. Alan **Koridor** seçilince aynı kutu **"Kat No"** olarak açılır ve zorunludur; kayıtta `room = "Koridor Kat 3"`, kartta plaka "KORİDOR / 3 / KAT". Oda No ve Kat No **yalnızca tam sayı** kabul eder (en fazla 4 hane). Harf, nokta, virgül ya da 5. rakam yazılırsa atılır ve kutunun altında kırmızı uyarı çıkar ("… tam sayı olmalı; nokta ya da virgül kullanılamaz." / "… yalnızca rakamdan oluşmalı." / "… en fazla 4 haneli olabilir.").
   - Kategori (tam genişlik).
   - Açıklama.
   - Liste.
   - OOO ve Misafir odada kutuları.
   - Tüm seçimler açılır liste (select).
   - **Tekrar kayıt uyarısı:** Yeni işte (güncellemede değil) Kaydet'e basınca aynı oda/alan + departman + kategori için açık iş varsa formda sarı uyarı çıkar (kim, ne zaman, durum), düğme "Yine de kaydet" olur; ikinci basışta kaydeder. Seçim değişince uyarı kalkar. Veritabanında `fdos_open_dupes(p_room, p_dept, p_cat)` (`schema.sql` 14. bölüm, security definer: kişinin göremediği işleri de bulur, yalnızca kim/ne zaman/durum döner); fonksiyon yoksa görülebilen işlere bakılır. Satınalma (oda yok) kontrol edilmez.
   - **Kişiye atama yok.** İş yalnızca departmana atanır ("Departman" = atanan departman). Departmanı değiştirmek için işi açan kişi ya da yönetici detaydaki Güncelle ile formu açar.
7. **Satınalma** seçilince (otelde depo yok, alan listesine "Depo" eklenmeyecek) Alan alanı "Gerekmiyor" yazısıyla kilitlenir ve zorunlu olmaz. OOO ve Misafir odada kutuları da kilitlenir.
9. **Görünürlük:** Bir iş yalnızca **atandığı departmana** ve **işi açan kişiye** görünür; başka departman göremez. Yönetici her şeyi görür. Hem ekranda (`canSee()`) hem veritabanında (`fdos_can_see(data)` RLS kuralı, `schema.sql` 8. bölüm: okuma, güncelleme, silme) uygulanır. İşi açan kişi `createdUid` ile, eski kayıtlarda `createdBy` adıyla tanınır.
10. **İş detayı yalnızca görüntüleme ekranıdır.** Hiçbir alan detayda düzenlenmez.
   - Ayrı kutu yok: detay ekranının zemini kartın rengiyle aynıdır (geçiş yok); kartlardaki soldaki renkli çentik burada ekranın tepesinde yatay şerittir. Zemin açık işte mavi, tamamlanmışta yeşil. Ekranda sırayla: **Departman**, **Açıklama** (kalın), varsa **Liste**, **Durum**; varsa Bitiş, Kontrol, Oda. Aynı yerde tekrarlıyorsa **Tekrar** satırı ("Son 30 günde bu odada açılan 3. Klima / ısıtma işi"). Sağ altta küçük: "Bildiren: …" ve altında "Açılış: …" (kaç saat önce yazılmaz).
   - İşi açan kişi (`createdUid`, eski kayıtlarda `createdBy` adı) ve yönetici: başlıkta ✕ yanında **Güncelle** (`canEdit(t)`). Basınca iş, verileriyle **Yapılacak İş formunda** açılır (başlık "Yapılacak İşi Güncelle", düğme "Güncelle"); kayıtta yalnızca değişen alanlar yazılır, geçmişe "Güncelledi: …" düşer. Tamamlanmış işte formda "Kaydı sil" çıkar.
   - İşin atandığı departman (`inDept(t)`): Güncelle yok. Yalnızca "Durumu değiştir" açılır listesi ve liste maddelerini onaylama; ikisi de anında kaydedilir. Kartlardaki durum düğmeleri (Beklemede ve DND Kartlı işte yalnızca **Tamamlandı**; **"Üstlen" yok**, yeni işin kartında düğme yoktur, durum detaydan değişir) da yalnızca bu departmanda çıkar; "Detay" düğmesi yok (karta dokununca detay açılır); düğmesi olmayan kartta düğme satırı hiç görünmez.
   - **"Kontrol edildi" yalnızca işi atayan (açan) kişide ve yöneticide** (`canCheck(t)`; yönetici her işte kullanır, başkasında görünmez). Tamamlanan her iş yeşildir; onaylanan iş "KONTROL EDİLDİ" etiketiyle ayrılır (`.card.done.verified`). **"Yeniden aç"** kartta "Tamamlandı" durum yazısıyla aynı satırda, en sağda durur ("KONTROL EDİLDİ" etiketi "Bitti" satırının sağında); "Kontrol edildi" düğmesi onun altında, sağda; işin atandığı departman, işi açan kişi ve yönetici kullanır (`canVerify(t)`).
   - **Kontrolü onaylanmış iş sabittir** (`locked(t)`): kimse (yönetici dahil) Güncelle, durum değiştirme ya da liste onayı yapamaz. Yalnızca "Yeniden aç" kalır; yeniden açılınca onay kalkar, **listedeki tüm maddelerin onayı da kaldırılır** ve iş tekrar düzenlenebilir.
   - Liste boşsa detayda Liste bölümü görünmez. Tüm kalemler tiklenmeden "Tamamlandı" kaydedilmez.
   - Geçmiş listesinde değişikliği yapan kişinin adı (ve departmanı) kalın yazılır.
8. **Liste (checklist):**
   - Ekle'ye basınca altta tik kutulu satır çıkar.
   - Tik atılan kalemin üstü tek çizgiyle çizilir.
   - Sade satırlar: numara ve renkli kutu yok.
   - Satır sağında ✕ ile silme.
   - Tüm kalemler tiklenmeden iş "Tamamlandı" yapılamaz.

12. **Tekrarlayan arıza uyarısı** (`repeatNo(t)`, `REPEAT_DAYS = 30`): aynı `room` + `type` + `cat` için son 30 günde açılan kaçıncı iş olduğu sayılır; 2 ve üstüyse kartta `30 GÜNDE 3. KEZ` etiketi (`.flag.rep`), detayda Tekrar satırı, Rapor'da "Tekrarlayan arızalar (son 30 gün)" paneli (en fazla 8 satır, raporun kapsamına göre). Yeni iş açmaz, yalnızca uyarır ("tekrarlayan işler" özelliği değildir). Sayım kişinin görebildiği işlerle yapılır.

11. **Rapor:** Göstergeler: Açılan iş, Tamamlanan, Şu an açık, Ort. çözüm süresi. Departman tablosu: Açık, Biten, Ort. süre. Kişiler tablosu: Açtığı, Bitirdiği. "Zamanında", "Geciken", "Son tarihi geçen" ve "Aciliyet dağılımı" kaldırıldı. Tablo başlık satırları (Departmanlar, Kişiler) Anasayfa'daki "Bugün yapılacaklar" kutusunun açık grisinde. Personel yalnızca **kendi departmanına atanan işlerin** raporunu görür (açtığı başka departman işleri dahil değil); departman tablosunda yalnızca kendi departmanı, başlığı departman adı. Yönetici bütün departmanları ve **Kişiler** tablosunu görür.

## Açık konular
- **Eklenmeyecek özellikler (kullanıcı kararı):** işe not yazma, işe fotoğraf ekleme, tekrarlayan işler, **departman içinde Sorumlu (kişi) seçimi** (yapıldı, yanlış anlaşıldığı için 26/10/26 kaldırıldı; kod ve `schema.sql` bölümü tamamen silindi). İletişim yüz yüze/telefonla yapılıyor, uygulama acil işleri takip için. Bunlar yeniden önerilmez.
- Satışa kapalı odalar listesi: konuşuldu, **karar verilmedi, yapılmayacak** (kullanıcı "sakın yapma" dedi). Önerilen yer Anasayfa'da iki kutunun altında ince şerit; engel: görünürlük kuralı yüzünden Resepsiyon başka departmana atanmış OOO işleri göremez, veritabanı istisnası gerekir.
- Telefon kilitliyken bildirim yok (Web Push yapılmadı). Konuşuldu, **istenmiyor** (26/10/26 kullanıcı: "şu anlık istenmedi"; kullanıcı sormadan yeniden önerilmez): önerilen yol OneSignal (kullanıcı App ID verir, REST anahtarını kendisi Supabase'e girer, bildirim veritabanı tetikleyicisinden `pg_net` ile gider); alternatif Cloudflare Worker. iPhone'da yalnızca ana ekrana eklenmiş uygulamada çalışır.

## Kurulum durumu
- [x] Dosyalar GitHub'a yüklendi.
- [x] GitHub Pages açık (main / root). Adres: https://puktao.github.io/T-Dos/
- [x] Supabase'de `schema.sql` çalıştırıldı (tablo ve fonksiyon var, `anon` erişimi kapalı).
- [x] Sign-up kapatıldı.
- [x] Profil tablosu kuruldu (`schema.sql` 5. bölüm).
- [x] `schema.sql` 6. bölüm (kullanıcı ekleme fonksiyonu) kuruldu.
- [x] `schema.sql` 7. bölüm (liste tabloları) kuruldu.
- [x] `schema.sql` 8. bölüm (görünürlük kuralı) kuruldu.
- [x] `schema.sql` 9–11. bölümler kuruldu (25/10/26 dışarıdan doğrulandı: fonksiyonlar var, `anon` erişimi kapalı, sign-up kapalı).
- [x] `fdos_patch_task` boolean sürümü kuruldu (kullanıcı doğruladı: `pg_get_function_result` → boolean).
- [x] `tuncer@feronya.com` Supabase'de var; profili Tuncer · yonetici · admin (kullanıcı doğruladı).
- [x] `supabase-config.js` dolduruldu (proje `tkfyiunfcclwczvpbdha`, publishable anahtar).
- [x] Supabase → Authentication → URL Configuration: Site URL ve Redirect URLs `https://puktao.github.io/T-Dos/` (kullanıcı kaydetti; dışarıdan doğrulanamıyor, "Şifremi unuttum" ile denenebilir).
- [x] `schema.sql` 12. bölüm (ekleme kuralı) Supabase'de çalıştırıldı.
- [x] `schema.sql` 13. bölüm (iş kaydı koruması) çalıştırıldı; tetikleyici var, uygulamada deneme sorunsuz (kullanıcı doğruladı).
- [x] `schema.sql` 14. bölüm (`fdos_open_dupes`) kuruldu (dışarıdan doğrulandı: fonksiyon var, `anon` kapalı).
- [x] Supabase'de Sorumlu kalıntısı silindi (dışarıdan doğrulandı: `fdos_sorumlular` tablosu yok).
- [x] Servis departmanı Supabase tablolarına eklendi (kullanıcı doğruladı: Servis · SRV · Servis Talebi · 6 kategori).
- [x] `schema.sql` 15. bölüm (aciliyet ve son tarih verisini silme) çalıştırıldı (kullanıcı bildirdi).
- [x] Muhasebe departmanı Supabase tablolarına eklendi (kullanıcı doğruladı).
- [x] `schema.sql` 16. bölüm ("Devam ediyor" işleri "Yeni" yapma, `fdos_open_dupes` dnd ile) çalıştırıldı (kullanıcı bildirdi: Success).
- Not: Depo yalnızca F-Do’s içindir; PortioCraft ve F-Hotel projeleriyle bağlantısı yoktur, onlara dokunulmaz.

## Geliştirme notları
- Yerel deneme: `python3 -m http.server` ile aç. `supabase-config.js` boşken "Kurulum tamamlanmadı" ekranı görünmesi beklenen davranıştır.
- Değişiklikten sonra: satır içi script'in söz dizimini kontrol et (`node --check`), telefon genişliğinde (≈400px) açık ve koyu temada bak, `sw.js` sürümünü artır.
- Renkler `:root` içindeki token'lardan gelir. Koyu tema iki blokta tanımlı: `prefers-color-scheme` ve `[data-theme=dark]`.
- `[hidden]{display:none!important}` kuralı gerekli; overlay'ler `hidden` özniteliğiyle açılıp kapanır. Alttan gelen ekranlar (`.sheet`) açılırken aşağıdan yukarı kayar (`sheetUp`, 0,3 sn; geniş ekranda hafif belirme; "hareketi azalt" ayarında animasyon yok).
- Commit mesajları Türkçe.
