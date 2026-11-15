-- The Warlord's Stronghold (alliance boss raids): the start of the last
-- stronghold each player stormed, the defenders they slew there (summed over
-- an alliance's members for the shared host), and the rewards and fall chests
-- they took ({"claimed", "falls"}).
alter table public.players
  add column if not exists boss_key double precision not null default 0,
  add column if not exists boss_damage integer not null default 0,
  add column if not exists boss jsonb not null default '{"claimed": 0, "falls": 0}'::jsonb;
