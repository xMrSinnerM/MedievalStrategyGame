-- Siege tools: the attack tools an army sent against a player brings to each
-- wall ({ "left" | "front" | "right": { tool: count } }); null means none.
alter table public.raids add column if not exists tools jsonb;
