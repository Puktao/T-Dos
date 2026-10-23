# F-Do’s – Otel İş Atama (Supabase sürümü)

Resepsiyon, Kat Hizmetleri, Teknik, Satınalma ve Mutfak arasında iş açma, atama ve takip uygulaması.
Telefonda ana ekrana eklenip uygulama gibi çalışır. Veriler senin Supabase projende tutulur, personel e-posta ve şifreyle girer.

## Klasördeki dosyalar

| Dosya | Ne işe yarar |
|---|---|
| `index.html` | Uygulamanın kendisi |
| `supabase-config.js` | Supabase bağlantı bilgileri (2. adımda doldurulur) |
| `schema.sql` | Veritabanı tablosu ve güvenlik kuralları (3. adımda çalıştırılır) |
| `manifest.webmanifest`, `sw.js`, `icons/` | Telefona uygulama olarak kurulma |

---

## Kurulum

Gerekenler: Supabase hesabı ve GitHub hesabı. Bilgisayardan yapman daha kolay olur. Toplam süre yaklaşık 20–30 dakika.

### 1. Supabase projesi
1. https://supabase.com/dashboard adresine gir → **New project**.
2. Name: `f-dos` → güçlü bir **Database Password** belirle ve bir yere kaydet → Region: **Central EU (Frankfurt)** → **Create new project**.
3. Proje hazırlanırken 1–2 dakika bekle.

Var olan bir Supabase projeni de kullanabilirsin. Tablonun adı `fdos_tasks` olduğu için mevcut tablolarına dokunmaz.

### 2. Bağlantı bilgilerini kopyala
1. Sol alttaki **Project Settings** (dişli simgesi) → **API Keys** ya da **Data API**.
2. **Project URL** (`https://xxxx.supabase.co`) ve **anon / publishable** anahtarı kopyala.
3. Bu klasördeki `supabase-config.js` dosyasını metin düzenleyiciyle aç (Not Defteri olur). İki değeri tırnakların içine yapıştır ve kaydet.

> ⚠️ **service_role** ya da **secret** anahtarı bu dosyaya asla yazma. O anahtar tüm güvenlik kurallarını devre dışı bırakır ve GitHub'da herkes görür.

### 3. Veritabanını kur
1. Sol menü → **SQL Editor** → **New query**.
2. Bu klasördeki `schema.sql` dosyasının tamamını yapıştır → **Run**.
3. "Success. No rows returned" yazısı çıkmalı. Dosya birden fazla kez çalıştırılırsa sorun olmaz.

### 4. Giriş ayarları ve personel hesapları
1. **Authentication** → **Sign In / Providers** → **Email** açık olsun.
2. Aynı ekranda **Allow new users to sign up** ayarını **KAPAT** → Save.
   > ⚠️ Bu adımı atlama. Açık kalırsa uygulamanın adresini bulan herkes kendine hesap açıp otelin işlerini görebilir.
3. **Authentication** → **Users** → **Add user** → **Create new user**:
   e-posta + şifre yaz, **Auto Confirm User** kutusunu işaretle → Create.
   Her personel için tekrarla. Ortak resepsiyon cihazı için `resepsiyon@oteliniz.com` gibi tek bir hesap da açabilirsin.

### 5. GitHub'a yükle
1. https://github.com → sağ üstte **+** → **New repository**.
2. Repository name: `f-dos` → **Public** → **Create repository**.
   (Ücretsiz GitHub'da yayın sayfası yalnızca Public depolarda çalışır. Kodun görünür olur, işler görünmez; onları 3. ve 4. adımdaki kurallar korur.)
3. Açılan sayfada **uploading an existing file** bağlantısına bas.
4. Bu klasördeki **tüm dosyaları ve `icons` klasörünü** sürükleyip bırak (2. adımda doldurduğun `supabase-config.js` dahil).
5. **Commit changes**.

### 6. Yayına al (GitHub Pages)
1. Depoda **Settings** → sol menü **Pages**.
2. Source: **Deploy from a branch** → Branch: **main** → **/(root)** → **Save**.
3. 1–2 dakika sonra adresin aynı sayfanın üstünde görünür: `https://KULLANICIADIN.github.io/f-dos/`

### 7. Adresi Supabase'e tanıt ("Şifremi unuttum" için)
1. Supabase → **Authentication** → **URL Configuration**.
2. **Site URL**: `https://KULLANICIADIN.github.io/f-dos/`
3. **Redirect URLs** → **Add URL** → aynı adres → Save.

Giriş bu adım olmadan da çalışır. Ama yapılmazsa şifre yenileme e-postasındaki bağlantı yanlış adrese gider.

### 8. Telefonlara kur
- **Android (Chrome):** adresi aç → sağ üst ⋮ menü → **Uygulamayı yükle** ya da **Ana ekrana ekle**.
- **iPhone (Safari):** adresi aç → alttaki Paylaş düğmesi → **Ana Ekrana Ekle**.
- Personel e-posta ve şifresiyle girer. Adı ve departmanı yöneticinin atadığı bilgilerden gelir.

### 9. Yönetici ve kullanıcı ekleme
Yönetici hesabı `tuncer@feronya.com` (ad: Tuncer). Yönetici herkesin işlerini ve Rapor'daki **Kişiler** tablosunu görür, uygulamadan kullanıcı ekler ve departman atar.
1. **Authentication → Users → Add user → Create new user:** `tuncer@feronya.com` + şifre, **Auto Confirm User** işaretli → Create. (Zaten varsa atla.)
2. **SQL Editor → New query:** `schema.sql` dosyasının tamamını yeniden yapıştır → **Run**. Bu, kullanıcı profillerini kurar ve Tuncer'i yönetici yapar.
3. **Edge Functions → Deploy a new function → Via Editor:**
   - Function name: `fdos-admin`
   - Kod alanındaki her şeyi sil, depodaki `supabase/functions/fdos-admin/index.ts` dosyasının tamamını yapıştır → **Deploy function**.
   - Fonksiyonun **Details / Settings** bölümünde **Verify JWT** (veya "Enforce JWT verification") ayarını **kapat** → Save. Kimlik kontrolünü fonksiyonun kendisi yapıyor.
4. Uygulamada Tuncer ile giriş yap → sağ üstteki ada bas → **Kullanıcılar**. Ad, e-posta, geçici şifre ve departman yazıp **Kullanıcı ekle**.

Personel artık adını ve departmanını kendisi seçmez; girişte yöneticinin atadığı bilgiler gelir. Ortak cihaz kullanılıyorsa her personel kendi hesabıyla girip çıkmalı.

---

## Güncelleme
1. Değişen dosyayı GitHub'daki depoya yeniden yükle (aynı adla; eskisinin üstüne yazar).
2. `sw.js` içindeki `const CACHE = "fdos-v1";` satırındaki sayıyı bir artır (v2, v3…) ve onu da yükle.
3. Telefonlar bir sonraki açışta yeni sürüme geçer. Geçmezse uygulamayı tamamen kapatıp yeniden aç.

## Sık karşılaşılan sorunlar
| Ekranda görülen | Neden / çözüm |
|---|---|
| "Kurulum tamamlanmadı" | `supabase-config.js` doldurulmamış ya da GitHub'a yüklenmemiş (2. ve 5. adım). |
| "Veritabanı tablosu bulunamadı" | `schema.sql` çalıştırılmamış (3. adım). |
| "E-posta ya da şifre yanlış" | Kullanıcı eklenmemiş ya da şifre yanlış (4. adım). |
| "Bu hesap onaylanmamış" | Kullanıcı eklenirken **Auto Confirm User** seçilmemiş. Kullanıcıyı silip yeniden ekle. |
| Bir telefondaki değişiklik diğerinde hemen görünmüyor | `schema.sql`'in 4. bölümü (canlı güncelleme) çalışmamış. 3. adımı tekrarla. Uygulama yine de açılışta ve ekrana dönüldüğünde listeyi yeniler. |
| Değişiklik telefonda görünmüyor | `sw.js` içindeki sürüm numarası artırılmamış (Güncelleme 2. adım). |

## Bilinmesi gerekenler
- **İnternet gerekir:** İş açmak ve güncellemek için bağlantı şart. Bağlantı yoksa uygulama "İnternet bağlantısı yok" der, değişiklik kaydedilmez.
- **Bildirimler:** Uygulama açıkken yeni iş gelince ekranda uyarı ve ses çıkar. Telefon kilitliyken bildirim gelmez.
- **Tamamlananlar ve Rapor** son 30 günün tamamlanan işlerini gösterir. Daha eski kayıtlar veritabanında durur, uygulamada listelenmez.
- **Ücretsiz plan:** Supabase ücretsiz projeleri uzun süre kullanılmazsa duraklatabilir. Her gün kullanılan bir uygulamada bu olmaz. Durumu Supabase panelinden takip edebilirsin.
- **Şifre yenileme e-postaları** ücretsiz planda saatte birkaç e-postayla sınırlı. Gerekirse yönetici kullanıcıyı Supabase'den silip yeni şifreyle yeniden ekleyebilir.
