create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  email text,
  chips bigint not null default 5000 check (chips >= 0),
  diamonds bigint not null default 0 check (diamonds >= 0),
  xp bigint not null default 0 check (xp >= 0),
  level int not null default 1 check (level >= 1),
  wins int not null default 0,
  games int not null default 0,
  current_streak int not null default 0,
  best_streak int not null default 0,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
create policy "profiles readable" on public.profiles for select using (true);
create policy "self update" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name, avatar_url, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(coalesce(new.email,''),'@',1)),
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    new.email
  ) on conflict (id) do update set
    display_name = excluded.display_name,
    avatar_url = excluded.avatar_url,
    email = excluded.email,
    updated_at = now();
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of raw_user_meta_data, email on auth.users
for each row execute procedure public.handle_new_user();
