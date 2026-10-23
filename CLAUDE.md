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
  - RLS: yalnızca `authenticated` okur, ekler ve günceller. Silme yalnızca `status = 'tamam'` olan işlerde. `anon` erişimi yok.
  - `fdos_patch_task(p_id, p_patch jsonb)` → `data = data || p_patch`. Üst düzey alanları birleştirir; güncellemeler bununla yapılır.
  - Realtime: tablo `supabase_realtime` yayınında.
- **Veri akışı:** Açık işler (`status in (yeni,devam,beklemede)`) ve son 30 günde tamamlananlar (`done_at >= now-30g`) çekilir. Realtime kanalı `fdos-tasks` ile değişiklikler uygulanır. Kanal yeniden bağlandığında, sekme görünür olduğunda ve internet geri geldiğinde `refetch()` çalışır. Yazmalar önce yerelde uygulanır (`applyRow(..., true)`), hata olursa `refetch()` ile geri alınır.
- **Giriş:** Supabase Auth, e-posta ve şifre. Kayıt (sign-up) kapalı, kullanıcıları yönetici panelden ekler. "Şifremi unuttum" → `resetPasswordForEmail` → `PASSWORD_RECOVERY` olayında "Yeni şifre" ekranı açılır.
- **Kimlik:** Ad ve departman cihazda `localStorage["oia.me"]` içinde tutulur. Kayıtlarda kullanıcı id'si değil, bu ad yazılır (`createdBy`, `log.by`).
- **PWA:** `manifest.webmanifest`, `sw.js` (aynı köken için önce ağ, CDN için önce önbellek), `icons/`. **Her yayında `sw.js` içindeki `CACHE` sürümünü artır.**
- **Yayın:** GitHub Pages, `main` dalının kökü. `.nojekyll` var.

## İş kaydı (`data` alanı)
`type, cat, dept, prio, dueAt(ms), room, desc, items[{id,text,done,by?,at?}], ooo, guest, status, assignee, createdAt, updatedAt, doneAt, verified, verifiedBy, createdBy, createdDept, log[{t,by,msg}]` (`log` en fazla 40 kayıt tutar)
- `prio`: `acil` (kırmızı) · `orta` (sarı) · `sureli` (mavi). Eski kayıtlardaki `normal` ve `dusuk` değerleri `prioOf()` ile `orta` ve `sureli`ye eşlenir.
- `status`: `yeni` → `devam` / `beklemede` → `tamam`. Resepsiyon "Kontrol edildi" der (`verified`), bu durumda `ooo` (satışa kapalı) kalkar.
- Satınalma işlerinde `room` boştur, kartta "TALEP / SAT" görünür.

## Sabitler (index.html içinde)
- `DEPTS`: teknik, kat (Kat Hizmetleri), resepsiyon, satinalma, mutfak.
- `TYPES` (her tür tek departmana bağlı): Arıza→teknik · Temizlik Talebi→kat · Müşteri Talebi→kat · Resepsiyon Talebi→resepsiyon · Satınalma Talebi→satinalma · Mutfak Talebi→mutfak. Kategoriler türün içinde tanımlı.
- `AREAS`: Lobi, Restoran, Bar, Mutfak, Toplantı Odası, Koridor. Bunlara ek olarak "Oda No" seçeneği var; seçilince yanındaki oda numarası alanı açılır.

## Kullanıcının kesinleştirdiği arayüz kararları
1. Uygulama adı **F-Do’s**. Logo: lacivert zemin, beyaz `F-Do`, sarı tire, üstte küçük sarı `’s`; "Do" F’den küçük, altında yalnızca "Do" boyunca düz sarı çizgi, çizginin alt kenarı F’nin alt ucuyla aynı hizada (Big Shoulders Display 800). Uygulama ikonu, üst köşedeki logo ve giriş ekranındaki logo aynı çizimdir: `index.html` içindeki `#fdosLogo` SVG sembolü ve `icons/*.png`. Yazı tipi ya da renk değiştirilmez.
2. Alt tablar: **Anasayfa · Yapılacaklar · Tamamlananlar · Rapor**.
3. **Anasayfa** sırası:
   - "Bugün yapılacaklar" ve "Bitmemiş işler" adlı iki büyük kutu. Bugün kutusu, son tarihi bugün olan ve süresi geçmiş işleri sayar.
   - "Acil yapılacaklar" listesi, kırmızı kutular.
   - "Takvimi yaklaşan" listesi, son tarihe göre sıralı, aciliyet rengine boyanmış kutular, en fazla 12 iş. Acil işler bu listede görünmez (yalnızca "Acil yapılacaklar"da).
4. Kartlar aciliyet rengiyle boyanır, her kartta son tarih ve kalan süre ya da gecikme yazar.
5. **Liste ekranları** (Yapılacaklar ve Tamamlananlar):
   - Üstte arama alanı, sağında Filtre düğmesi.
   - Filtre panelinde **yalnızca Aciliyet ve Durum** var. Tamamlananlar'da Durum = Kontrol bekleyen / edilen.
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
   - Formda **"Kişiye ata" yok**; atama iş detayından yapılır.
7. **Satınalma** seçilince (otelde depo yok, alan listesine "Depo" eklenmeyecek) Alan alanı "Gerekmiyor" yazısıyla kilitlenir ve zorunlu olmaz. OOO ve Misafir odada kutuları da kilitlenir.
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
- [ ] Kullanıcılar eklenecek (Authentication → Users → Add user, Auto Confirm). Dışarıdan doğrulanamıyor.
- [x] `supabase-config.js` dolduruldu (proje `tkfyiunfcclwczvpbdha`, publishable anahtar).
- [ ] Supabase → Authentication → URL Configuration: Site URL ve Redirect URLs alanlarına `https://puktao.github.io/T-Dos/` yazılacak. Dışarıdan doğrulanamıyor.
- Not: Depo yalnızca F-Do’s içindir; PortioCraft ve F-Hotel projeleriyle bağlantısı yoktur, onlara dokunulmaz.

## Geliştirme notları
- Yerel deneme: `python3 -m http.server` ile aç. `supabase-config.js` boşken "Kurulum tamamlanmadı" ekranı görünmesi beklenen davranıştır.
- Değişiklikten sonra: satır içi script'in söz dizimini kontrol et (`node --check`), telefon genişliğinde (≈400px) açık ve koyu temada bak, `sw.js` sürümünü artır.
- Renkler `:root` içindeki token'lardan gelir. Koyu tema iki blokta tanımlı: `prefers-color-scheme` ve `[data-theme=dark]`.
- `[hidden]{display:none!important}` kuralı gerekli; overlay'ler `hidden` özniteliğiyle açılıp kapanır.
- Commit mesajları Türkçe.
