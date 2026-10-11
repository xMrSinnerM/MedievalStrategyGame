-- Phase 9: alliances. Each player belongs to at most one alliance, with a
-- role in it; invitations and requests to join wait in alliance_pending.
-- Only the game server reads or writes these, like the other game tables.

create table public.alliances (
  id bigint generated always as identity primary key,
  name text not null,
  tag text not null,
  open boolean not null default true,
  description text not null default '',
  created_at timestamptz not null default now(),
  constraint alliances_name_length check (char_length(name) between 3 and 24),
  constraint alliances_tag_length check (char_length(tag) between 2 and 4),
  constraint alliances_description_length check (char_length(description) <= 300)
);

create unique index alliances_name_key on public.alliances (lower(name));
create unique index alliances_tag_key on public.alliances (lower(tag));

alter table public.players
  add column alliance_id bigint references public.alliances (id) on delete set null,
  add column alliance_role text check (alliance_role in ('leader', 'officer', 'member')),
  add column alliance_joined double precision not null default 0;

create index players_alliance_idx on public.players (alliance_id);

create table public.alliance_pending (
  alliance_id bigint not null references public.alliances (id) on delete cascade,
  user_id uuid not null references public.players (user_id) on delete cascade,
  kind text not null check (kind in ('invite', 'request')),
  at double precision not null,
  primary key (alliance_id, user_id)
);

create index alliance_pending_user_idx on public.alliance_pending (user_id);

-- Each alliance with its member count and might, for the list of alliances.
create view public.alliance_summaries with (security_invoker = true) as
  select a.id, a.name, a.tag, a.open, a.description,
    count(p.user_id) as members, coalesce(sum(p.might), 0) as might
  from public.alliances a left join public.players p on p.alliance_id = a.id
  group by a.id;

alter table public.alliances enable row level security;
alter table public.alliance_pending enable row level security;
revoke all on public.alliances, public.alliance_pending, public.alliance_summaries from anon, authenticated;
