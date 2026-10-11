-- Phase 8: the leaderboard. Each player's might (building levels and
-- soldiers at home, see data/pvp.json) is kept up to date by the game server
-- on every save, with the robber baron camps they have beaten.

alter table public.players add column might integer not null default 0;
alter table public.players add column barons_beaten integer not null default 0;

-- Fill both in for the castles that already exist.
update public.players p set
  might = 10 * (select coalesce(sum((b->>'level')::int), 0) from jsonb_array_elements(p.castle->'buildings') b)
    + (select coalesce(sum(t.value::numeric), 0) from jsonb_each_text(p.castle->'troops') t)::int,
  barons_beaten = (select count(*) from public.reports r
    where r.user_id = p.user_id and r.report->>'winner' = 'a'
      and coalesce(r.report->>'kind', '') <> 'raid' and coalesce((r.report->>'empty')::boolean, false) = false);

create index players_might_idx on public.players (might desc);
