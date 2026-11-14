-- The other kingdoms (data/kingdoms.json): a player's castles in Frostmark
-- and Sunreach by kingdom id, each with its castle state and the ships
-- carrying its good home. Null or empty until the player founds one.
alter table public.players add column if not exists kingdoms jsonb;
