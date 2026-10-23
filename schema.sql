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
create or replace function public.fdos_patch_task(p_id text, p_patch jsonb)
returns void
language sql
security invoker
set search_path = public
as $$
  update public.fdos_tasks
     set data = data || p_patch, updated_at = now()
   where id = p_id;
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
  v_dept  text := case when p_dept in ('teknik','kat','resepsiyon','satinalma','mutfak') then p_dept else null end;
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
