-- Outposts: a player's second castle (data/outposts.json) with its spot,
-- region, castle state and the carts on the road between the two castles.
-- Null until the player founds one.
alter table public.players add column if not exists outpost jsonb;
