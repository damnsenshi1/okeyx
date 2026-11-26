-- Görsel tercihler: çuha rengi, ıstaka ağacı, büyük rakam
alter table public.okeyx_user_preferences
  add column if not exists table_theme text not null default 'green',
  add column if not exists rack_style text not null default 'walnut',
  add column if not exists big_tile_numbers boolean not null default false;

-- Masada müzik/ambiyans varsayılan kapalı (yalnızca taş sesleri).
alter table public.okeyx_user_preferences alter column table_ambience_enabled set default false;
