-- Seasons (data/seasons.json): renown earned each calendar month. The game
-- server writes these from the castle JSON (castle.season) with every save,
-- so the ranking can be read without opening every castle: the month a
-- player's renown counts for (months since year 0) and that renown, and the
-- month before and what they earned in it, for last season's prizes.
alter table public.players
  add column season_key integer not null default -1,
  add column season_points integer not null default 0,
  add column last_season_key integer not null default -1,
  add column last_season_points integer not null default 0;

create index players_season_points on public.players (season_key, season_points desc);
create index players_last_season_points on public.players (last_season_key, last_season_points desc);
