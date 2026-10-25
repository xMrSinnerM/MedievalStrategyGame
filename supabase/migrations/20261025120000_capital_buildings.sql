-- Town buildings in capitals: whoever holds a capital (a villages row whose
-- id is a town, see data/capitals.json) can raise town walls, a market, a
-- guardhouse and a guild hall there. `buildings` holds their levels
-- ({building: level}) and `building` the one going up ({id, level, finish}),
-- or null. They belong to the town, so they stay when it changes hands;
-- the game server folds a finished building into `buildings` whenever the
-- row changes. New columns on an existing table: its grants still apply.

alter table public.villages add column if not exists buildings jsonb not null default '{}'::jsonb;
alter table public.villages add column if not exists building jsonb;
