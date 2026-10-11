-- Siege waves: how an army sent against a player storms the walls
-- ([{ "left" | "front" | "right": { unit: count } }, ...]); null means one
-- wave with the army spread over the walls (autoWaves in server/rules/battle.ts).
alter table public.raids add column if not exists waves jsonb;
