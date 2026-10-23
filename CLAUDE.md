# F-Do’s – Proje rehberi (Claude Code için)

Otel içi iş atama uygulaması. Resepsiyon, Kat Hizmetleri, Teknik, Satınalma ve Mutfak arasında arıza, temizlik, müşteri, satınalma ve mutfak taleplerini açma, atama ve takip etme.
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
  - RLS: yalnızca `authenticated`. Okuma, güncelleme ve silme `fdos_can_see(data)` ile sınırlı (atanan departman, işi açan, yönetici); ekleme herkes. Silme ayrıca yalnızca `status = 'tamam'` olan işlerde. `anon` erişimi yok.
  - `fdos_patch_task(p_id, p_patch jsonb)` → `data = data || p_patch`. Üst düzey alanları birleştirir; güncellemeler bununla yapılır.
  - Realtime: tablo `supabase_realtime` yayınında.
- **Veri akışı:** Açık işler (`status in (yeni,devam,beklemede)`) ve son 30 günde tamamlananlar (`done_at >= now-30g`) çekilir. Realtime kanalı `fdos-tasks` ile değişiklikler uygulanır. Kanal yeniden bağlandığında, sekme görünür olduğunda ve internet geri geldiğinde `refetch()` çalışır. Yazmalar önce yerelde uygulanır (`applyRow(..., true)`), hata olursa `refetch()` ile geri alınır.
- **Giriş:** Supabase Auth, e-posta ve şifre. Kayıt (sign-up) kapalı, kullanıcıları yönetici panelden ekler. "Şifremi unuttum" → `resetPasswordForEmail` → `PASSWORD_RECOVERY` olayında "Yeni şifre" ekranı açılır.
- **Kimlik:** Ad, departman ve rol `public.fdos_profiles` tablosundan gelir (hesaba bağlı). Personel kendi kaydını değiştiremez; yönetici atar. Kayıtlarda kullanıcı id'si değil ad yazılır (`createdBy`, `log.by`). Profil tablosu yoksa eski düzen çalışır: ad ve departman cihazda `localStorage["oia.me"]`.
- **Yönetici (admin):** Yalnızca `tuncer@feronya.com` (ad "Tuncer", departman `yonetici` = "Yönetici", rozet YÖN). Diğer herkes personeldir. Uygulamada **"Yetki" seçimi yoktur**; rol veritabanında e-postaya göre zorlanır (`fdos_profiles_guard` tetikleyicisi, `schema.sql` 9. bölüm). "Yönetici" departmanı başkasına atanamaz, iş formunda ve Rapor departman tablosunda görünmez (türü yok). Hesabım → **Kullanıcılar**: önce kayıtlı kullanıcılar listesi gelir (satır başına Kaydet düğmesi yok). Satırı **sola kaydırınca** sağda **Düzenle** ve **Sil** çıkar (satıra dokunmak da açar). Sağ üstteki **+** yeni kullanıcı formunu açar (Ad, E-posta, Geçici şifre, Departman → Kaydet). Düzenle aynı formu bilgilerle açar (Ad, Departman → **Güncelle**; e-posta ve şifre değiştirilmez). Sil iki aşamalı (Sil → Eminim), `fdos_admin_delete_user` ile; yönetici ve kendi hesabı silinemez. Rapor'da yalnızca yöneticiye görünen **Kişiler** tablosu var.
- **Kullanıcı ekleme:** `fdos_admin_create_user(p_email, p_password, p_name, p_dept, p_role)` SQL fonksiyonu (security definer, yalnızca yönetici). `auth.users` ve `auth.identities` satırlarını doğrudan ekler, kullanıcı onaylı açılır. Bu Supabase'in iç tablolarına yazdığı için resmî yol değildir; Supabase Auth şeması değişirse güncellenmesi gerekebilir. Edge Function kullanılmıyor (kullanıcı panelden yükleyemedi). Profil satırı `auth.users` tetikleyicisiyle kendiliğinden oluşur.
- **PWA:** `manifest.webmanifest`, `sw.js` (aynı köken için önce ağ, CDN için önce önbellek), `icons/`. **Her yayında `sw.js` içindeki `CACHE` sürümünü artır.**
- **Yayın:** GitHub Pages, `main` dalının kökü. `.nojekyll` var.

## İş kaydı (`data` alanı)
`type, cat, dept, prio, dueAt(ms), room, desc, items[{id,text,done,by?,at?}], ooo, guest, status, createdAt, updatedAt, doneAt, doneBy, verified, verifiedBy, createdBy, createdDept, createdUid, log[{t,by,msg}]` (`log` en fazla 40 kayıt tutar)
- `prio`: `acil` (kırmızı) · `orta` (sarı) · `sureli` (mavi). Eski kayıtlardaki `normal` ve `dusuk` değerleri `prioOf()` ile `orta` ve `sureli`ye eşlenir.
- `status`: `yeni` → `devam` / `beklemede` → `tamam`. Resepsiyon "Kontrol edildi" der (`verified`), bu durumda `ooo` (satışa kapalı) kalkar.
- Satınalma işlerinde `room` boştur, kartta "TALEP / SAT" görünür.

## Listeler (Supabase tabloları)
- `fdos_departmanlar(kod, ad, kisa_ad, rozet, alan_gerekli, sira, aktif)`, `fdos_turler(kod, ad, departman, sira, aktif)`, `fdos_kategoriler(tur, ad, sira, aktif)`, `fdos_alanlar(ad, sira, aktif)`. Kullanıcı bunları Supabase Table Editor'dan düzenler.
- Uygulama girişte ve `refetch()` sırasında `loadLists()` ile okur, `DEPTS`/`TYPES`/`AREAS` nesnelerinin içini değiştirir. Tablolar yoksa ya da boşsa aşağıdaki sabitler kullanılır.
- `aktif = false` olan kayıt seçim listelerinde görünmez, eski işlerde adı görünmeye devam eder. Silme yerine pasif yapılır; `kod` değiştirilmez (işlerde kodla kayıtlı).
- `alan_gerekli = false` olan departmanda (Satınalma) iş açarken alan/oda sorulmaz. Eskiden koddaki `"satinalma"` kontrolüydü, artık `DEPTS[k].noArea`.
- Okuma: giriş yapan herkes. Yazma: yalnızca yönetici (`fdos_is_admin()`); Supabase paneli bu kurala takılmaz.

## Sabitler (index.html içinde, tablolar yoksa yedek)
- `DEPTS`: teknik, kat (Kat Hizmetleri), resepsiyon, satinalma, mutfak, yonetici (yalnızca Tuncer).
- `TYPES` (her tür tek departmana bağlı): Arıza→teknik · Temizlik Talebi→kat · Müşteri Talebi→kat · Resepsiyon Talebi→resepsiyon · Satınalma Talebi→satinalma · Mutfak Talebi→mutfak. Kategoriler türün içinde tanımlı.
- `AREAS`: Lobi, Restoran, Bar, Mutfak, Toplantı Odası, Koridor. Bunlara ek olarak "Oda No" seçeneği var; seçilince yanındaki oda numarası alanı açılır.

## Kullanıcının kesinleştirdiği arayüz kararları
1. Uygulama adı **F-Do’s**. Logo: lacivert zemin, beyaz `F-Do`, sarı tire, üstte küçük sarı `’s`; "Do" F’den küçük, altında yalnızca "Do" boyunca düz sarı çizgi, çizginin alt kenarı F’nin alt ucuyla aynı hizada (Big Shoulders Display 800). Uygulama ikonu, üst köşedeki logo ve giriş ekranındaki logo aynı çizimdir: `index.html` içindeki `#fdosLogo` SVG sembolü ve `icons/*.png`. Yazı tipi ya da renk değiştirilmez.
2. Alt tablar: **Anasayfa · Yapılacaklar · Tamamlananlar · Rapor**. Uygulama **her açılışta Anasayfa** ile başlar (adres çubuğundaki #sekme dikkate alınmaz); arka planda 1 dakikadan uzun kalıp geri gelinince de Anasayfa'ya döner (açık iş/kullanıcı formu varsa dokunulmaz). Üst çubukta logonun yanında sekme adı yazmaz (başlık yalnızca ekran okuyucu için, `sr-only`).
3. **Anasayfa** sırası:
   - "Bugün yapılacaklar" ve "Bitmemiş işler" adlı iki büyük kutu. Bugün kutusu, son tarihi bugün olan ve süresi geçmiş işleri sayar.
   - "Acil yapılacaklar" listesi, kırmızı kutular.
   - "Takvimi yaklaşan" listesi, son tarihe göre sıralı, aciliyet rengine boyanmış kutular, en fazla 12 iş. Acil işler bu listede görünmez (yalnızca "Acil yapılacaklar"da).
4. **Tarih biçimi her yerde `gg/aa/yy ss:dd`** (ör. 23/10/26 14:30; `fmt()`); "Bugün / Yarın / Dün" yazılmaz. Formdaki tarih seçici telefonun kendi biçimini kullanır. Kartlar aciliyet rengiyle boyanır, her kartta son tarih yazar. **Kalan süre / gecikme yazısı ("1 gün 21 sa kaldı", "Gecikti…", "…gecikmeli", "zamanında") hiçbir yerde yazılmaz** (kartlar, detay). Süresi geçen işin son tarihi kırmızı yazılır.
5. **Liste ekranları** (Yapılacaklar ve Tamamlananlar):
   - Üstte arama alanı, sağında Filtre düğmesi.
   - Filtre panelinde **yalnızca Aciliyet ve Durum** var. Tamamlananlar'da Durum = Kontrol bekleyen / edilen.
   - Panelde "Sıfırla" ve "… işi göster" düğmeleri yok; seçim anında uygulanır, panel ✕ ya da dışına dokunarak kapanır.
   - Açık filtreler arama alanının altında kaldırılabilir etiket olarak görünür.
   - "Son tarih" filtresi panelde yok; yalnızca Anasayfa kutusundan gelir.
6. **"Yapılacak İş" formu** sırası:
   - [Sorumlu departman | Bildirim türü] yan yana. Tür listesi seçilen departmana göre daralır.
   - Alan açılır listesi ve sağında oda no alanı.
   - [Kategori | Aciliyet] yan yana.
   - Son tarih (aciliyete göre otomatik dolar, hızlı süre düğmesi yok).
   - Açıklama.
   - Liste.
   - OOO ve Misafir odada kutuları.
   - Tüm seçimler açılır liste (select).
   - **Kişiye atama yok.** İş yalnızca departmana atanır ("Departman" = atanan departman). Departmanı değiştirmek için işi açan kişi ya da yönetici detaydaki Güncelle ile formu açar.
7. **Satınalma** seçilince (otelde depo yok, alan listesine "Depo" eklenmeyecek) Alan alanı "Gerekmiyor" yazısıyla kilitlenir ve zorunlu olmaz. OOO ve Misafir odada kutuları da kilitlenir.
9. **Görünürlük:** Bir iş yalnızca **atandığı departmana** ve **işi açan kişiye** görünür; başka departman göremez. Yönetici her şeyi görür. Hem ekranda (`canSee()`) hem veritabanında (`fdos_can_see(data)` RLS kuralı, `schema.sql` 8. bölüm: okuma, güncelleme, silme) uygulanır. İşi açan kişi `createdUid` ile, eski kayıtlarda `createdBy` adıyla tanınır.
10. **İş detayı yalnızca görüntüleme ekranıdır.** Hiçbir alan detayda düzenlenmez.
   - Ayrı kutu yok: detay ekranının zemini aciliyet kutularının (kartların) rengiyle aynıdır (geçiş yok); kartlardaki soldaki renkli çentik burada ekranın tepesinde yatay şerittir. Ekranda sırayla: aciliyet etiketi, **Departman**, **Son tarih** (yalnızca tarih; geçmişse kırmızı), **Açıklama** (kalın), varsa **Liste**, **Durum**; varsa Bitiş, Kontrol, Oda. Sağ altta küçük: "Bildiren: …" ve altında "Açılış: …" (kaç saat önce yazılmaz).
   - İşi açan kişi (`createdUid`, eski kayıtlarda `createdBy` adı) ve yönetici: başlıkta ✕ yanında **Güncelle** (`canEdit(t)`). Basınca iş, verileriyle **Yapılacak İş formunda** açılır (başlık "Yapılacak İşi Güncelle", düğme "Güncelle"); kayıtta yalnızca değişen alanlar yazılır, geçmişe "Güncelledi: …" düşer. Tamamlanmış işte formda "Kaydı sil" çıkar.
   - İşin atandığı departman (`inDept(t)`): Güncelle yok. Yalnızca "Durumu değiştir" açılır listesi ve liste maddelerini onaylama; ikisi de anında kaydedilir. Kartlardaki durum düğmeleri (Üstlen, Tamamlandı, Beklemeye al…) da yalnızca bu departmanda çıkar; "Detay" düğmesi yok (karta dokununca detay açılır); düğmesi olmayan kartta düğme satırı hiç görünmez.
   - **"Kontrol edildi" yalnızca işi atayan (açan) kişide** (`canCheck(t)`; yönetici dahil başkasında görünmez). Onaylanan iş kartı **yeşil** olur (`.card.done.verified`, detay ekranı da yeşil). **"Yeniden aç"** kartın sağ alt köşesinde durur; işin atandığı departman, işi açan kişi ve yönetici kullanır (`canVerify(t)`).
   - Liste boşsa detayda Liste bölümü görünmez. Tüm kalemler tiklenmeden "Tamamlandı" kaydedilmez.
   - Geçmiş listesinde değişikliği yapan kişinin adı (ve departmanı) kalın yazılır.
8. **Liste (checklist):**
   - Ekle'ye basınca altta tik kutulu satır çıkar.
   - Tik atılan kalemin üstü tek çizgiyle çizilir.
   - Sade satırlar: numara ve renkli kutu yok.
   - Satır sağında ✕ ile silme.
   - Tüm kalemler tiklenmeden iş "Tamamlandı" yapılamaz.

## Açık konular
- Telefon kilitliyken bildirim yok (Web Push yapılmadı).

## Kurulum durumu
- [x] Dosyalar GitHub'a yüklendi.
- [x] GitHub Pages açık (main / root). Adres: https://puktao.github.io/T-Dos/
- [x] Supabase'de `schema.sql` çalıştırıldı (tablo ve fonksiyon var, `anon` erişimi kapalı).
- [x] Sign-up kapatıldı.
- [x] Profil tablosu kuruldu (`schema.sql` 5. bölüm).
- [x] `schema.sql` 6. bölüm (kullanıcı ekleme fonksiyonu) kuruldu.
- [x] `schema.sql` 7. bölüm (liste tabloları) kuruldu.
- [x] `schema.sql` 8. bölüm (görünürlük kuralı) kuruldu.
- [ ] `schema.sql` 9. bölüm (yalnızca Tuncer yönetici, Yönetici departmanı) ve 10. bölüm (kullanıcı silme) için dosya yeniden çalıştırılacak.
- [ ] `tuncer@feronya.com` Supabase'de var mı doğrulanacak (yoksa Add user, Auto Confirm; ardından `schema.sql` yeniden).
- [x] `supabase-config.js` dolduruldu (proje `tkfyiunfcclwczvpbdha`, publishable anahtar).
- [ ] Supabase → Authentication → URL Configuration: Site URL ve Redirect URLs alanlarına `https://puktao.github.io/T-Dos/` yazılacak. Dışarıdan doğrulanamıyor.
- Not: Depo yalnızca F-Do’s içindir; PortioCraft ve F-Hotel projeleriyle bağlantısı yoktur, onlara dokunulmaz.

## Geliştirme notları
- Yerel deneme: `python3 -m http.server` ile aç. `supabase-config.js` boşken "Kurulum tamamlanmadı" ekranı görünmesi beklenen davranıştır.
- Değişiklikten sonra: satır içi script'in söz dizimini kontrol et (`node --check`), telefon genişliğinde (≈400px) açık ve koyu temada bak, `sw.js` sürümünü artır.
- Renkler `:root` içindeki token'lardan gelir. Koyu tema iki blokta tanımlı: `prefers-color-scheme` ve `[data-theme=dark]`.
- `[hidden]{display:none!important}` kuralı gerekli; overlay'ler `hidden` özniteliğiyle açılıp kapanır.
- Commit mesajları Türkçe.
