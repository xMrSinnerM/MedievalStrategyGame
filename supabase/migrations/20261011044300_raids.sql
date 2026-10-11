-- Phase 8: players attack each other. Each army sent against a player is a
-- row in raids until it is home again; only the game server reads or writes
-- them. New players get a few days of beginner protection.

alter table public.players add column protected_until double precision not null default 0;

create table public.raids (
  id bigint generated always as identity primary key,
  attacker uuid not null references public.players (user_id) on delete cascade,
  defender uuid not null references public.players (user_id) on delete cascade,
  attacker_name text not null,
  defender_name text not null,
  army jsonb not null,
  from_x double precision not null,
  from_y double precision not null,
  to_x double precision not null,
  to_y double precision not null,
  depart double precision not null,
  arrive double precision not null,
  back double precision not null,
  state text not null default 'out' check (state in ('out', 'fighting', 'home', 'done')),
  survivors jsonb not null default '{}'::jsonb,
  loot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index raids_attacker_idx on public.raids (attacker, state);
create index raids_defender_idx on public.raids (defender, state);

alter table public.raids enable row level security;
revoke all on public.raids from anon, authenticated;
