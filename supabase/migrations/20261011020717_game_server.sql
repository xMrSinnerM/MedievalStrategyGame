-- The multiplayer game's tables. Players can read their own rows; only the
-- game server (the "game" Edge Function, using the service role) writes, so
-- every change goes through the game rules on the server's clock.

create table public.players (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text not null,
  home_x double precision not null,
  home_y double precision not null,
  castle jsonb not null,
  camps jsonb not null default '[]'::jsonb,
  marches jsonb not null default '[]'::jsonb,
  next_march integer not null default 1,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint players_name_length check (char_length(name) between 3 and 20)
);

create unique index players_name_key on public.players (lower(name));

create table public.reports (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.players (user_id) on delete cascade,
  at double precision not null,
  report jsonb not null,
  created_at timestamptz not null default now()
);

create index reports_user_id_idx on public.reports (user_id, id desc);

alter table public.players enable row level security;
alter table public.reports enable row level security;

create policy "Players read their own row" on public.players
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Players read their own reports" on public.reports
  for select to authenticated using ((select auth.uid()) = user_id);

revoke insert, update, delete, truncate on public.players, public.reports from anon, authenticated;
revoke all on public.players, public.reports from anon;
