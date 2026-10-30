-- Weekly alliance tournaments (data/tournaments.json): a knockout bracket
-- between alliances. Each week's row holds its entrants (drawn by the first
-- request after the week starts) and the scores of the rounds already over,
-- keyed by the round's start, so a finished match never changes.
-- players.tourney_* is the renown each castle earned in the round it's
-- counting and in the one before (written with every save, from
-- castle.tourney); players.tourney_claimed is the week whose prize the player
-- took.

create table public.tournaments (
  week double precision primary key,
  entrants jsonb not null default '[]'::jsonb,
  results jsonb not null default '{}'::jsonb,
  drawn_at double precision not null
);

alter table public.tournaments enable row level security;
revoke all on public.tournaments from anon, authenticated;
grant select, insert, update, delete on public.tournaments to service_role;

alter table public.players
  add column if not exists tourney_key double precision not null default 0,
  add column if not exists tourney_points integer not null default 0,
  add column if not exists last_tourney_key double precision not null default 0,
  add column if not exists last_tourney_points integer not null default 0,
  add column if not exists tourney_claimed double precision not null default 0;
