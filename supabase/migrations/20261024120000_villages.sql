-- Resource villages: who holds each village on the map (server/world/world.json),
-- the soldiers its owner stationed there, when it last changed hands (its
-- peace runs from then) and up to when its yield has gone to the owner. The
-- game server adds a row for each village the first time it needs them; a
-- village without an owner is held by the militia. `version` lets two
-- requests change the same village without losing either change.
--
-- Armies sent to a village are raids rows with `village` set: "attack" to
-- take it, "station" to guard it, "return" for guards walking home. An
-- attack on a village the militia hold has no defender.

create table public.villages (
  id text primary key,
  owner uuid references public.players (user_id) on delete set null,
  owner_name text,
  guard jsonb not null default '{}'::jsonb,
  taken_at double precision not null default 0,
  paid_at double precision not null default 0,
  version integer not null default 1
);

create index villages_owner_idx on public.villages (owner);

alter table public.villages enable row level security;
revoke all on public.villages from anon, authenticated;
grant select, insert, update, delete on public.villages to service_role;

alter table public.raids alter column defender drop not null;
alter table public.raids add column if not exists village text;
alter table public.raids add column if not exists mission text not null default 'attack'
  check (mission in ('attack', 'station', 'return'));
create index if not exists raids_village_idx on public.raids (state, arrive) where village is not null;
