-- Alliance wars (data/wars.json): alliances win war points with the capitals
-- in weekly seasons. Every point won is a row of war_points: an hour of
-- holding a capital, taking one, or holding one against an attack, with the
-- season it counts for (the season's start) and the alliance's name and tag
-- as they were. war_standings adds them up for each season and alliance.
-- villages.scored_at is up to when a capital's holder has had its hold
-- points (in whole seconds, so the server can compare it exactly);
-- players.war_claimed is the season whose prize the player took.

create table public.war_points (
  id bigint generated always as identity primary key,
  season double precision not null,
  alliance_id bigint not null,
  name text not null,
  tag text not null,
  capital text not null,
  kind text not null check (kind in ('hold', 'capture', 'defence')),
  points double precision not null,
  at double precision not null
);

create index war_points_season_idx on public.war_points (season, alliance_id);
create index war_points_capture_idx on public.war_points (season, alliance_id, capital) where kind = 'capture';

-- Each alliance's war points, captures and defences in each season, with its
-- name and tag now (or as they were, if it has been disbanded).
create view public.war_standings with (security_invoker = true) as
  select w.season, w.alliance_id,
    coalesce(max(a.name), (array_agg(w.name order by w.at desc))[1]) as name,
    coalesce(max(a.tag), (array_agg(w.tag order by w.at desc))[1]) as tag,
    sum(w.points) as points,
    count(*) filter (where w.kind = 'capture') as captures,
    count(*) filter (where w.kind = 'defence') as defences
  from public.war_points w left join public.alliances a on a.id = w.alliance_id
  group by w.season, w.alliance_id;

alter table public.war_points enable row level security;
revoke all on public.war_points, public.war_standings from anon, authenticated;
grant select, insert, update, delete on public.war_points to service_role;
grant select on public.war_standings to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Hold points start counting now, not from when each capital was taken.
alter table public.villages add column if not exists scored_at double precision not null default 0;
update public.villages set scored_at = floor(extract(epoch from now())) where scored_at = 0;

alter table public.players add column if not exists war_claimed double precision not null default 0;
