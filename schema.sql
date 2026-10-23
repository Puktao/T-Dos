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
