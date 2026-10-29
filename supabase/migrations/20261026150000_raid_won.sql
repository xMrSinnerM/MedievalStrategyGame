-- Achievements: whether an attack on a player's castle was won, so the
-- attacker's castle counts the win when the army comes home.
alter table public.raids add column if not exists won boolean;
