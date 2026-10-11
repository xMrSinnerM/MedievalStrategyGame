-- Baron Invasions: the start of the last invasion each player played in, and
-- their event points in it (for the event screen and its leaderboard).
alter table public.players
  add column event_key double precision not null default 0,
  add column event_points integer not null default 0;

create index players_event_points on public.players (event_key, event_points desc);
