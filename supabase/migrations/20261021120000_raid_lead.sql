-- Commanders: the commander leading an army against another player, with
-- what their gear does and (once fought) the xp the battle earned.
alter table public.raids add column if not exists lead jsonb;
