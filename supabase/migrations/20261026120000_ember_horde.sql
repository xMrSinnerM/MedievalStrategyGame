-- The Ember Horde: the start of the last horde each player played in, their
-- horde points in it (for its ranking), and their war trophies, Trophy Market
-- purchases and ranked prize ({"trophies", "bought", "ranked"}).
alter table public.players
  add column horde_key double precision not null default 0,
  add column horde_points integer not null default 0,
  add column horde jsonb not null default '{"trophies": 0, "bought": {}, "ranked": false}'::jsonb;

create index players_horde_points on public.players (horde_key, horde_points desc);
