-- Phase 9: helping allies. Carts of resources and defenders on their way to
-- an ally, standing in their castle or walking home. "delivering" marks a
-- cart being unloaded so that two requests can't both unload it. Only the
-- game server reads or writes these, like the other game tables.

create table public.aid (
  id bigint generated always as identity primary key,
  sender uuid not null references public.players (user_id) on delete cascade,
  receiver uuid not null references public.players (user_id) on delete cascade,
  sender_name text not null,
  receiver_name text not null,
  kind text not null check (kind in ('resources', 'troops')),
  resources jsonb not null default '{}',
  army jsonb not null default '{}',
  from_x double precision not null,
  from_y double precision not null,
  to_x double precision not null,
  to_y double precision not null,
  depart double precision not null,
  arrive double precision not null,
  leave double precision not null,
  back double precision not null,
  state text not null default 'out' check (state in ('out', 'delivering', 'done'))
);

create index aid_sender_idx on public.aid (sender, state);
create index aid_receiver_idx on public.aid (receiver, state);

alter table public.aid enable row level security;
revoke all on public.aid from anon, authenticated;
