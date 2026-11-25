-- OkeyX v5.9.0 / Faz 1 mobil temel. Supabase projesine uygulanmıştır.
create schema if not exists private;

create table if not exists public.okeyx_user_preferences (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  locale text not null default 'tr' check (locale in ('tr','en')),
  music_enabled boolean not null default true,
  sound_enabled boolean not null default true,
  vibration_enabled boolean not null default true,
  notifications_enabled boolean not null default true,
  data_saver_enabled boolean not null default false,
  reduced_motion_enabled boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);
alter table public.okeyx_user_preferences enable row level security;
drop policy if exists "users_read_own_preferences" on public.okeyx_user_preferences;
create policy "users_read_own_preferences" on public.okeyx_user_preferences
for select to authenticated using ((select auth.uid()) = auth_user_id);
drop policy if exists "users_insert_own_preferences" on public.okeyx_user_preferences;
create policy "users_insert_own_preferences" on public.okeyx_user_preferences
for insert to authenticated with check ((select auth.uid()) = auth_user_id);
drop policy if exists "users_update_own_preferences" on public.okeyx_user_preferences;
create policy "users_update_own_preferences" on public.okeyx_user_preferences
for update to authenticated using ((select auth.uid()) = auth_user_id)
with check ((select auth.uid()) = auth_user_id);
drop policy if exists "users_delete_own_preferences" on public.okeyx_user_preferences;
create policy "users_delete_own_preferences" on public.okeyx_user_preferences
for delete to authenticated using ((select auth.uid()) = auth_user_id);
revoke all on table public.okeyx_user_preferences from public, anon;
grant select, insert, update, delete on table public.okeyx_user_preferences to authenticated;
grant all on table public.okeyx_user_preferences to service_role;

create or replace function private.okeyx_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;
drop trigger if exists okeyx_user_preferences_touch_updated_at on public.okeyx_user_preferences;
create trigger okeyx_user_preferences_touch_updated_at
before update on public.okeyx_user_preferences
for each row execute function private.okeyx_touch_updated_at();

create or replace function private.okeyx_ensure_profile(
  p_display_name text default null,
  p_avatar_url text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_avatar text;
  v_is_guest boolean;
  v_profile public.okeyx_profiles%rowtype;
  v_vip_level integer := 0;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  v_name := left(coalesce(nullif(btrim(p_display_name), ''), 'Oyuncu'), 40);
  v_avatar := case
    when p_avatar_url is null or btrim(p_avatar_url) = '' then null
    when length(p_avatar_url) <= 500 and p_avatar_url ~ '^https://' then p_avatar_url
    else null
  end;
  v_is_guest := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  select * into v_profile from public.okeyx_profiles
  where auth_user_id = v_uid for update;
  if not found then
    insert into public.okeyx_profiles
      (user_id, auth_user_id, display_name, avatar_url, is_guest)
    values (v_uid::text, v_uid, v_name, v_avatar, v_is_guest)
    returning * into v_profile;
  else
    update public.okeyx_profiles
    set is_guest = v_is_guest,
        display_name = case when display_name = '' or display_name = 'Oyuncu' then v_name else display_name end,
        avatar_url = coalesce(avatar_url, v_avatar),
        updated_at = timezone('utc', now())
    where auth_user_id = v_uid returning * into v_profile;
  end if;
  insert into public.okeyx_user_preferences (auth_user_id)
  values (v_uid) on conflict (auth_user_id) do nothing;
  select coalesce(vip_level, 0) into v_vip_level
  from public.okeyx_vip_progress where user_id = v_profile.user_id;
  return to_jsonb(v_profile) || jsonb_build_object('vip_level', coalesce(v_vip_level, 0));
end;
$$;

create or replace function public.okeyx_ensure_profile(
  p_display_name text default null,
  p_avatar_url text default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select private.okeyx_ensure_profile(p_display_name, p_avatar_url);
$$;

create or replace function private.okeyx_update_profile(
  p_display_name text,
  p_avatar_url text default null,
  p_avatar_seed text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_display_name, ''));
  v_avatar text;
  v_seed text;
  v_profile public.okeyx_profiles%rowtype;
  v_vip_level integer := 0;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if length(v_name) < 2 or length(v_name) > 32 then
    raise exception 'display_name_length_invalid' using errcode = '22023';
  end if;
  v_avatar := case
    when p_avatar_url is null or btrim(p_avatar_url) = '' then null
    when length(p_avatar_url) <= 500 and p_avatar_url ~ '^https://' then p_avatar_url
    else null
  end;
  v_seed := nullif(left(btrim(coalesce(p_avatar_seed, '')), 64), '');
  update public.okeyx_profiles
  set display_name = v_name, avatar_url = v_avatar, avatar_seed = v_seed,
      updated_at = timezone('utc', now())
  where auth_user_id = v_uid returning * into v_profile;
  if not found then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;
  select coalesce(vip_level, 0) into v_vip_level
  from public.okeyx_vip_progress where user_id = v_profile.user_id;
  return to_jsonb(v_profile) || jsonb_build_object('vip_level', coalesce(v_vip_level, 0));
end;
$$;

create or replace function public.okeyx_update_profile(
  p_display_name text,
  p_avatar_url text default null,
  p_avatar_seed text default null
) returns jsonb language sql security invoker set search_path = '' as $$
  select private.okeyx_update_profile(p_display_name, p_avatar_url, p_avatar_seed);
$$;

create or replace function private.okeyx_anonymize_current_profile()
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  update public.okeyx_profiles
  set display_name = 'Silinen Oyuncu', avatar_url = null, avatar_seed = null,
      auth_user_id = null, is_guest = true,
      metadata = jsonb_build_object('deleted', true),
      updated_at = timezone('utc', now())
  where auth_user_id = v_uid;
  delete from public.okeyx_user_preferences where auth_user_id = v_uid;
end;
$$;

create or replace function public.okeyx_anonymize_current_profile()
returns void language sql security invoker set search_path = '' as $$
  select private.okeyx_anonymize_current_profile();
$$;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
revoke all on function private.okeyx_ensure_profile(text, text) from public;
revoke all on function private.okeyx_update_profile(text, text, text) from public;
revoke all on function private.okeyx_anonymize_current_profile() from public;
grant execute on function private.okeyx_ensure_profile(text, text) to authenticated, service_role;
grant execute on function private.okeyx_update_profile(text, text, text) to authenticated, service_role;
grant execute on function private.okeyx_anonymize_current_profile() to authenticated, service_role;
revoke all on function public.okeyx_ensure_profile(text, text) from public, anon;
revoke all on function public.okeyx_update_profile(text, text, text) from public, anon;
revoke all on function public.okeyx_anonymize_current_profile() from public, anon;
grant execute on function public.okeyx_ensure_profile(text, text) to authenticated, service_role;
grant execute on function public.okeyx_update_profile(text, text, text) to authenticated, service_role;
grant execute on function public.okeyx_anonymize_current_profile() to authenticated, service_role;

create table if not exists public.okeyx_client_events (
  id bigint generated always as identity primary key,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  event_name text not null check (event_name ~ '^[a-z0-9_]{2,48}$'),
  app_version text not null,
  build_number integer not null,
  platform text not null default 'android' check (platform in ('android','ios')),
  properties jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists okeyx_client_events_user_created_idx
on public.okeyx_client_events (auth_user_id, created_at desc);
alter table public.okeyx_client_events enable row level security;
drop policy if exists "users_insert_own_client_events" on public.okeyx_client_events;
create policy "users_insert_own_client_events" on public.okeyx_client_events
for insert to authenticated with check ((select auth.uid()) = auth_user_id);
revoke all on table public.okeyx_client_events from public, anon, authenticated;
grant insert on table public.okeyx_client_events to authenticated;
grant all on table public.okeyx_client_events to service_role;
grant usage, select on sequence public.okeyx_client_events_id_seq to authenticated, service_role;

create table if not exists public.okeyx_push_devices (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('android','ios')),
  device_token text not null unique check (length(device_token) between 20 and 4096),
  enabled boolean not null default true,
  app_version text not null,
  last_seen_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now())
);
create index if not exists okeyx_push_devices_user_idx
on public.okeyx_push_devices (auth_user_id);
alter table public.okeyx_push_devices enable row level security;
drop policy if exists "users_manage_own_push_devices" on public.okeyx_push_devices;
create policy "users_manage_own_push_devices" on public.okeyx_push_devices
for all to authenticated using ((select auth.uid()) = auth_user_id)
with check ((select auth.uid()) = auth_user_id);
revoke all on table public.okeyx_push_devices from public, anon;
grant select, insert, update, delete on table public.okeyx_push_devices to authenticated;
grant all on table public.okeyx_push_devices to service_role;

revoke insert, update, delete, truncate, references, trigger
on table public.okeyx_feature_flags from anon, authenticated;
grant select on table public.okeyx_feature_flags to anon, authenticated;
insert into public.okeyx_feature_flags
  (key, enabled, store_build_enabled, description, config, updated_at)
values (
  'mobile_foundation', true, true,
  'OkeyX Phase 1 mobile application control plane',
  jsonb_build_object(
    'phase', 1, 'minimum_build', 17, 'maintenance', false,
    'google_enabled', true, 'facebook_enabled', false, 'apple_enabled', false,
    'vip_max_level', 200,
    'loading_tips', jsonb_build_array(
      'Günün ipucu: Çifte giderken ıstakandaki taş çeşidine dikkat et.',
      'Perlerini erken açmak her zaman en düşük ceza anlamına gelmez.',
      'Göstergeyi ve son atılan taşları takip etmek oyunun yarısıdır.',
      'Misafir hesabını bağlayarak ilerlemeni güvenceye al.'
    )
  ), timezone('utc', now())
)
on conflict (key) do update set
  enabled = excluded.enabled,
  store_build_enabled = excluded.store_build_enabled,
  description = excluded.description,
  config = excluded.config,
  updated_at = excluded.updated_at;
