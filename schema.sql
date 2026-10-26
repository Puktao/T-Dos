-- F-Do’s veritabanı kurulumu
-- Supabase → SQL Editor → New query → bu dosyanın tamamını yapıştır → Run
-- Birden fazla kez çalıştırmak güvenlidir.

-- 1) İşler tablosu (her iş tek satır, ayrıntılar "data" alanında)
create table if not exists public.fdos_tasks (
  id          text primary key,
  data        jsonb not null,
  status      text   generated always as (data->>'status') stored,
  done_at     bigint generated always as (((data->>'doneAt')::numeric)::bigint) stored,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists fdos_tasks_status_idx  on public.fdos_tasks (status);
create index if not exists fdos_tasks_done_at_idx on public.fdos_tasks (done_at);

-- 2) Güvenlik: yalnızca giriş yapmış personel erişir
alter table public.fdos_tasks enable row level security;
revoke all on public.fdos_tasks from anon;
grant select, insert, update, delete on public.fdos_tasks to authenticated;

drop policy if exists "fdos okuma"     on public.fdos_tasks;
drop policy if exists "fdos ekleme"    on public.fdos_tasks;
drop policy if exists "fdos guncelleme" on public.fdos_tasks;
drop policy if exists "fdos silme"     on public.fdos_tasks;
create policy "fdos okuma"      on public.fdos_tasks for select to authenticated using (true);
create policy "fdos ekleme"     on public.fdos_tasks for insert to authenticated with check (true);
create policy "fdos guncelleme" on public.fdos_tasks for update to authenticated using (true) with check (true);
create policy "fdos silme"      on public.fdos_tasks for delete to authenticated using (status = 'tamam');

-- 3) Bir işin yalnızca değişen alanlarını güncelleyen fonksiyon
--    (iki kişi aynı işin farklı alanlarını değiştirirse ikisi de korunur)
--    Kayıt değiştiyse true döner; iş artık görünmüyorsa (başka departmana aktarılmış, silinmiş) false.
drop function if exists public.fdos_patch_task(text, jsonb);
create function public.fdos_patch_task(p_id text, p_patch jsonb)
returns boolean
language sql
security invoker
set search_path = public
as $$
  with u as (
    update public.fdos_tasks
       set data = data || p_patch, updated_at = now()
     where id = p_id
    returning 1
  )
  select exists (select 1 from u);
$$;
revoke all on function public.fdos_patch_task(text, jsonb) from public, anon;
grant execute on function public.fdos_patch_task(text, jsonb) to authenticated;

-- 4) Canlı güncelleme (bir telefonda yapılan değişiklik diğerlerinde anında görünür)
do $$
begin
  alter publication supabase_realtime add table public.fdos_tasks;
exception when duplicate_object then null;
end $$;

-- 5) Kullanıcı profilleri: ad, departman ve rol (yönetici / personel)
--    Ad ve departmanı yönetici atar. Personel kendi kaydını değiştiremez.
create table if not exists public.fdos_profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  name       text not null,
  dept       text,
  role       text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Giriş yapan kişi yönetici mi? (güvenlik kurallarında kullanılır)
create or replace function public.fdos_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.fdos_profiles where user_id = auth.uid() and role = 'admin');
$$;
revoke all on function public.fdos_is_admin() from public, anon;
grant execute on function public.fdos_is_admin() to authenticated;

alter table public.fdos_profiles enable row level security;
revoke all on public.fdos_profiles from anon;
revoke update on public.fdos_profiles from authenticated;
grant select on public.fdos_profiles to authenticated;
grant update (name, dept, role) on public.fdos_profiles to authenticated;

drop policy if exists "profil okuma"     on public.fdos_profiles;
drop policy if exists "profil guncelleme" on public.fdos_profiles;
create policy "profil okuma"      on public.fdos_profiles for select to authenticated using (true);
create policy "profil guncelleme" on public.fdos_profiles for update to authenticated
  using (public.fdos_is_admin()) with check (public.fdos_is_admin());

-- Yönetici kendi yönetici yetkisini yanlışlıkla kaldıramasın
create or replace function public.fdos_profiles_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.user_id = auth.uid() and old.role = 'admin' and new.role <> 'admin' then
    raise exception 'Kendi yönetici yetkini kaldıramazsın';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists fdos_profiles_guard on public.fdos_profiles;
create trigger fdos_profiles_guard before update on public.fdos_profiles
  for each row execute function public.fdos_profiles_guard();

-- Supabase'e yeni kullanıcı eklenince profili kendiliğinden oluşur
create or replace function public.fdos_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.fdos_profiles (user_id, email, name, dept, role)
  values (
    new.id, new.email,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data->>'dept', ''),
    case when lower(new.email) = 'tuncer@feronya.com' then 'admin' else 'user' end
  )
  on conflict (user_id) do nothing;
  return new;
end $$;
drop trigger if exists fdos_on_auth_user on auth.users;
create trigger fdos_on_auth_user after insert on auth.users
  for each row execute function public.fdos_new_user();

-- Daha önce eklenmiş kullanıcıların profilleri
insert into public.fdos_profiles (user_id, email, name)
select id, email, split_part(email, '@', 1) from auth.users
on conflict (user_id) do nothing;

-- Yönetici: tuncer@feronya.com → ad "Tuncer"
update public.fdos_profiles set role = 'admin', name = 'Tuncer'
 where lower(email) = 'tuncer@feronya.com';

-- 6) Yönetici uygulamadan yeni kullanıcı ekler (ayrı sunucu fonksiyonu gerekmez)
--    Yalnızca yönetici çalıştırabilir. Kullanıcı onaylı (Auto Confirm) açılır.
create or replace function public.fdos_admin_create_user(
  p_email text, p_password text, p_name text, p_dept text default null, p_role text default 'user')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_name  text := left(trim(coalesce(p_name, '')), 40);
  v_dept  text := case when exists (select 1 from public.fdos_departmanlar where kod = p_dept) then p_dept else null end;
  v_role  text := case when p_role = 'admin' then 'admin' else 'user' end;
begin
  if not public.fdos_is_admin() then raise exception 'Bu işlem yalnızca yönetici içindir'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'E-posta adresi geçersiz'; end if;
  if length(coalesce(p_password, '')) < 6 then raise exception 'Şifre en az 6 karakter olmalı'; end if;
  if v_name = '' then raise exception 'Ad boş olamaz'; end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Bu e-posta ile kayıtlı bir kullanıcı zaten var';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb,
          jsonb_build_object('name', v_name, 'dept', v_dept), now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, v_id::text,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());

  -- profil tetikleyiciyle oluştu; adı, departmanı ve yetkiyi yaz
  update public.fdos_profiles set name = v_name, dept = v_dept, role = v_role where user_id = v_id;
  return v_id;
end $$;
revoke all on function public.fdos_admin_create_user(text, text, text, text, text) from public, anon;
grant execute on function public.fdos_admin_create_user(text, text, text, text, text) to authenticated;

-- 7) Listeler: departmanlar, bildirim türleri, kategoriler, alanlar
--    Supabase → Table Editor'dan satır ekleyip değiştirebilirsin. Uygulama girişte bu tabloları okur.
--    Kural: bir satırı SİLME, "aktif" kutusunu kapat (eski işlerde adı görünmeye devam eder).
--    "kod" sütunlarını sonradan DEĞİŞTİRME; eski işler bu kodla kayıtlı.
create table if not exists public.fdos_departmanlar (
  kod          text primary key check (kod ~ '^[a-z0-9_]+$'),
  ad           text not null,
  kisa_ad      text not null,
  rozet        text not null,
  alan_gerekli boolean not null default true,
  sira         int not null default 100,
  aktif        boolean not null default true
);
create table if not exists public.fdos_turler (
  kod       text primary key check (kod ~ '^[a-z0-9_]+$'),
  ad        text not null,
  departman text not null references public.fdos_departmanlar(kod),
  sira      int not null default 100,
  aktif     boolean not null default true
);
create table if not exists public.fdos_kategoriler (
  id    bigint generated always as identity primary key,
  tur   text not null references public.fdos_turler(kod),
  ad    text not null,
  sira  int not null default 100,
  aktif boolean not null default true,
  unique (tur, ad)
);
create table if not exists public.fdos_alanlar (
  id    bigint generated always as identity primary key,
  ad    text not null unique,
  sira  int not null default 100,
  aktif boolean not null default true
);
comment on column public.fdos_departmanlar.kod is 'Küçük harf, boşluksuz (ör. spa). Sonradan değiştirme.';
comment on column public.fdos_departmanlar.ad is 'Uygulamada görünen tam ad (ör. Kat Hizmetleri)';
comment on column public.fdos_departmanlar.kisa_ad is 'Kısa ad (ör. Kat)';
comment on column public.fdos_departmanlar.rozet is 'En fazla 3-4 harf (ör. HK)';
comment on column public.fdos_departmanlar.alan_gerekli is 'Kapalıysa iş açarken alan/oda sorulmaz (Satınalma gibi)';
comment on column public.fdos_turler.kod is 'Küçük harf, boşluksuz. Sonradan değiştirme.';
comment on column public.fdos_turler.departman is 'Bu türün gideceği departmanın kodu';
comment on column public.fdos_kategoriler.tur is 'Bağlı olduğu bildirim türünün kodu';
comment on column public.fdos_departmanlar.sira is 'Küçük sayı önce gelir';

do $$
declare t text;
begin
  foreach t in array array['fdos_departmanlar','fdos_turler','fdos_kategoriler','fdos_alanlar'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists "liste okuma" on public.%I', t);
    execute format('drop policy if exists "liste yonetici" on public.%I', t);
    execute format('create policy "liste okuma" on public.%I for select to authenticated using (true)', t);
    execute format('create policy "liste yonetici" on public.%I for all to authenticated using (public.fdos_is_admin()) with check (public.fdos_is_admin())', t);
  end loop;
end $$;

-- Başlangıç değerleri (var olanlara dokunmaz)
insert into public.fdos_departmanlar (kod, ad, kisa_ad, rozet, alan_gerekli, sira) values
  ('teknik', 'Teknik', 'Teknik', 'TEK', true, 10),
  ('kat', 'Kat Hizmetleri', 'Kat', 'HK', true, 20),
  ('resepsiyon', 'Resepsiyon', 'Resepsiyon', 'ÖN', true, 30),
  ('satinalma', 'Satınalma', 'Satınalma', 'SAT', false, 40),
  ('mutfak', 'Mutfak', 'Mutfak', 'MUT', true, 50),
  ('servis', 'Servis', 'Servis', 'SRV', true, 55),
  ('muhasebe', 'Muhasebe', 'Muhasebe', 'MUH', false, 60)
on conflict (kod) do nothing;
insert into public.fdos_turler (kod, ad, departman, sira) values
  ('ariza', 'Arıza', 'teknik', 10),
  ('temizlik', 'Temizlik Talebi', 'kat', 20),
  ('istek', 'Müşteri Talebi', 'kat', 30),
  ('satinalma', 'Satınalma Talebi', 'satinalma', 40),
  ('resepsiyon', 'Resepsiyon Talebi', 'resepsiyon', 50),
  ('mutfak', 'Mutfak Talebi', 'mutfak', 60),
  ('servis', 'Servis Talebi', 'servis', 65),
  ('muhasebe', 'Muhasebe Talebi', 'muhasebe', 70)
on conflict (kod) do nothing;
insert into public.fdos_kategoriler (tur, ad, sira) values
  ('ariza', 'Klima / ısıtma', 10),
  ('ariza', 'Elektrik / aydınlatma', 20),
  ('ariza', 'Su / tesisat', 30),
  ('ariza', 'TV / internet', 40),
  ('ariza', 'Kapı / kilit / kasa', 50),
  ('ariza', 'Mobilya', 60),
  ('ariza', 'Minibar / buzdolabı', 70),
  ('ariza', 'Diğer', 80),
  ('temizlik', 'Banyo', 10),
  ('temizlik', 'Yatak / çarşaf', 20),
  ('temizlik', 'Havlu / buklet eksik', 30),
  ('temizlik', 'Toz / zemin', 40),
  ('temizlik', 'Minibar dolumu', 50),
  ('temizlik', 'Koku', 60),
  ('temizlik', 'Çöp', 70),
  ('temizlik', 'Diğer', 80),
  ('istek', 'Ekstra havlu', 10),
  ('istek', 'Yastık / battaniye', 20),
  ('istek', 'Bebek yatağı', 30),
  ('istek', 'Ütü / ütü masası', 40),
  ('istek', 'Diş / tıraş seti', 50),
  ('istek', 'Diğer', 60),
  ('satinalma', 'Yedek parça', 10),
  ('satinalma', 'Temizlik malzemesi', 20),
  ('satinalma', 'Buklet / amenity', 30),
  ('satinalma', 'Tekstil (havlu, çarşaf)', 40),
  ('satinalma', 'Mutfak malzemesi', 50),
  ('satinalma', 'Kırtasiye', 60),
  ('satinalma', 'Demirbaş', 70),
  ('satinalma', 'Diğer', 80),
  ('resepsiyon', 'Misafir şikayeti', 10),
  ('resepsiyon', 'Oda değişikliği', 20),
  ('resepsiyon', 'Geç çıkış / erken giriş', 30),
  ('resepsiyon', 'Uyandırma', 40),
  ('resepsiyon', 'Kayıp eşya', 50),
  ('resepsiyon', 'Bagaj / transfer', 60),
  ('resepsiyon', 'Diğer', 70),
  ('mutfak', 'Oda servisi', 10),
  ('mutfak', 'Alerji / özel diyet', 20),
  ('mutfak', 'Pasta / sürpriz', 30),
  ('mutfak', 'Kahvaltı paketi', 40),
  ('mutfak', 'Minibar ürünü', 50),
  ('mutfak', 'Hijyen / temizlik', 60),
  ('mutfak', 'Diğer', 70),
  ('servis', 'Masa / salon hazırlığı', 10),
  ('servis', 'Oda servisi teslim / tepsi toplama', 20),
  ('servis', 'Misafir talebi (restoran / bar)', 30),
  ('servis', 'Toplantı / etkinlik servisi', 40),
  ('servis', 'Ekipman / malzeme eksik', 50),
  ('servis', 'Diğer', 60),
  ('muhasebe', 'Fatura / hesap düzeltme', 10),
  ('muhasebe', 'Ödeme', 20),
  ('muhasebe', 'Avans / masraf', 30),
  ('muhasebe', 'Diğer', 40)
on conflict (tur, ad) do nothing;
insert into public.fdos_alanlar (ad, sira) values
  ('Lobi', 10),
  ('Restoran', 20),
  ('Bar', 30),
  ('Mutfak', 40),
  ('Toplantı Odası', 50),
  ('Koridor', 60)
on conflict (ad) do nothing;

-- 8) Görünürlük: bir işi yalnızca atandığı departman, işi açan kişi ve yönetici görür / değiştirir.
--    (2. bölümdeki herkese açık kuralların yerine geçer.)
create or replace function public.fdos_can_see(d jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.fdos_profiles p
     where p.user_id = auth.uid()
       and ( p.role = 'admin'
             or (p.dept is not null and p.dept = d->>'dept')
             or d->>'createdUid' = auth.uid()::text
             or (coalesce(d->>'createdUid', '') = '' and lower(d->>'createdBy') = lower(p.name)) )
  );
$$;
revoke all on function public.fdos_can_see(jsonb) from public, anon;
grant execute on function public.fdos_can_see(jsonb) to authenticated;

drop policy if exists "fdos okuma"      on public.fdos_tasks;
drop policy if exists "fdos guncelleme" on public.fdos_tasks;
drop policy if exists "fdos silme"      on public.fdos_tasks;
create policy "fdos okuma"      on public.fdos_tasks for select to authenticated using (public.fdos_can_see(data));
create policy "fdos guncelleme" on public.fdos_tasks for update to authenticated
  using (public.fdos_can_see(data)) with check (public.fdos_can_see(data));
create policy "fdos silme"      on public.fdos_tasks for delete to authenticated
  using (status = 'tamam' and public.fdos_can_see(data));

-- 9) Yetki: yalnızca tuncer@feronya.com yöneticidir, departmanı "Yönetici". Diğer herkes personeldir.
--    Uygulamada "Yetki" seçimi yoktur; bu kural veritabanında zorlanır.
insert into public.fdos_departmanlar (kod, ad, kisa_ad, rozet, alan_gerekli, sira)
values ('yonetici', 'Yönetici', 'Yönetici', 'YÖN', true, 90)
on conflict (kod) do nothing;

create or replace function public.fdos_profiles_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if lower(new.email) = 'tuncer@feronya.com' then
    new.role := 'admin'; new.dept := 'yonetici';
  else
    new.role := 'user';
    if new.dept = 'yonetici' then new.dept := null; end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists fdos_profiles_guard on public.fdos_profiles;
create trigger fdos_profiles_guard before insert or update on public.fdos_profiles
  for each row execute function public.fdos_profiles_guard();

update public.fdos_profiles set role = role;   -- kuralı mevcut kayıtlara uygula

-- 10) Yönetici bir kullanıcıyı siler (girişi kapanır, profili silinir; açtığı işler ve geçmiş kayıtları kalır).
create or replace function public.fdos_admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fdos_is_admin() then raise exception 'Bu işlem yalnızca yönetici içindir'; end if;
  if p_user_id = auth.uid() then raise exception 'Kendi hesabını silemezsin'; end if;
  if exists (select 1 from public.fdos_profiles where user_id = p_user_id and role = 'admin') then
    raise exception 'Yönetici hesabı silinemez';
  end if;
  delete from auth.identities where user_id = p_user_id;
  delete from auth.users where id = p_user_id;   -- profil satırı da silinir (on delete cascade)
end $$;
revoke all on function public.fdos_admin_delete_user(uuid) from public, anon;
grant execute on function public.fdos_admin_delete_user(uuid) to authenticated;

-- 11) Silme: işi açan kişi (kontrolü onaylanmamış işte) ve yönetici (her işte) siler.
--     (8. bölümdeki "yalnızca tamamlanmış iş silinir" kuralının yerine geçer.)
create or replace function public.fdos_can_delete(d jsonb)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fdos_is_admin()
      or ( coalesce((d->>'verified')::boolean, false) = false
           and ( d->>'createdUid' = auth.uid()::text
                 or ( coalesce(d->>'createdUid', '') = ''
                      and exists (select 1 from public.fdos_profiles p
                                   where p.user_id = auth.uid() and lower(p.name) = lower(d->>'createdBy')) ) ) );
$$;
revoke all on function public.fdos_can_delete(jsonb) from public, anon;
grant execute on function public.fdos_can_delete(jsonb) to authenticated;

drop policy if exists "fdos silme" on public.fdos_tasks;
create policy "fdos silme" on public.fdos_tasks for delete to authenticated using (public.fdos_can_delete(data));

-- 12) Ekleme: yalnızca profili olan (silinmemiş) kullanıcı iş açar, iş kendi adına kaydedilir.
--     (2. bölümdeki "herkes ekler" kuralının yerine geçer. Silinen kullanıcının telefonunda açık kalan oturum yeni iş açamaz.)
drop policy if exists "fdos ekleme" on public.fdos_tasks;
create policy "fdos ekleme" on public.fdos_tasks for insert to authenticated
  with check ( exists (select 1 from public.fdos_profiles p where p.user_id = auth.uid())
               and data->>'createdUid' = auth.uid()::text );

-- 13) İş kaydının korunması
--     a) "Bildiren" adı ve departmanı, işi açan kişinin profilinden yazılır (uygulamanın gönderdiği ada güvenilmez).
--     b) İşi kimin açtığı sonradan değiştirilemez.
--     c) Kontrolü onaylanmış iş sabittir: yalnızca "Yeniden aç" (onayın kaldırılması) yapılabilir.
--     Supabase panelinden (SQL Editor, Table Editor) yapılan değişiklikler bu kurala takılmaz.
create or replace function public.fdos_tasks_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare p public.fdos_profiles;
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'INSERT' then
    select * into p from public.fdos_profiles where user_id = auth.uid();
    if found then
      new.data := new.data || jsonb_build_object('createdBy', p.name, 'createdDept', p.dept, 'createdUid', auth.uid()::text);
    end if;
    return new;
  end if;
  if coalesce((old.data->>'verified')::boolean, false) and coalesce((new.data->>'verified')::boolean, false) then
    raise exception 'Kontrolü onaylanmış iş değiştirilemez. Önce "Yeniden aç" de.';
  end if;
  new.data := jsonb_set(jsonb_set(jsonb_set(new.data,
                '{createdBy}',   coalesce(old.data->'createdBy',   'null'::jsonb)),
                '{createdDept}', coalesce(old.data->'createdDept', 'null'::jsonb)),
                '{createdUid}',  coalesce(old.data->'createdUid',  'null'::jsonb));
  return new;
end $$;
revoke all on function public.fdos_tasks_guard() from public, anon, authenticated;
drop trigger if exists fdos_tasks_guard on public.fdos_tasks;
create trigger fdos_tasks_guard before insert or update on public.fdos_tasks
  for each row execute function public.fdos_tasks_guard();

-- 14) Tekrar kayıt uyarısı: aynı oda/alan, departman ve kategori için açık iş var mı?
--     Başka departmanın açtığı ve kişinin göremediği işleri de bulur; ayrıntı vermez, yalnızca kim, ne zaman, durum.
create or replace function public.fdos_open_dupes(p_room text, p_dept text, p_cat text)
returns table (created_by text, created_at bigint, status text)
language sql
stable
security definer
set search_path = public
as $$
  select t.data->>'createdBy', ((t.data->>'createdAt')::numeric)::bigint, t.status
    from public.fdos_tasks t
   where exists (select 1 from public.fdos_profiles p where p.user_id = auth.uid())
     and coalesce(p_room, '') <> ''
     and t.status in ('yeni', 'devam', 'beklemede')
     and t.data->>'room' = p_room
     and t.data->>'dept' = p_dept
     and t.data->>'cat'  = p_cat
   order by 2 desc
   limit 5;
$$;
revoke all on function public.fdos_open_dupes(text, text, text) from public, anon;
grant execute on function public.fdos_open_dupes(text, text, text) to authenticated;

-- 15) Aciliyet ve son tarih kaldırıldı (26/10/26): işlerdeki "prio" ve "dueAt" alanları silinir.
--     Geçmiş (log) yazılarına dokunulmaz.
update public.fdos_tasks set data = data - 'prio' - 'dueAt' where data ?| array['prio', 'dueAt'];
