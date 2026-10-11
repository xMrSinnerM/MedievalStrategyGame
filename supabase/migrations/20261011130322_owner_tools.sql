-- The game owner's tools. Accounts in `admins` may start and stop events and
-- give players resources and soldiers; add one by hand in the SQL editor:
--   insert into public.admins (user_id) select id from auth.users where email = '...';
-- The game can never add an admin. Every admin action is kept in admin_log,
-- and the owner's changes to the event calendar in event_overrides. Only the
-- game server reads or writes these tables.

create table public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create table public.admin_log (
  id bigint generated always as identity primary key,
  admin uuid references auth.users (id) on delete set null,
  at double precision not null,
  action text not null,
  details jsonb not null default '{}'::jsonb
);

create table public.event_overrides (
  event text not null,
  starts_at double precision not null,
  ends_at double precision not null,
  primary key (event, starts_at)
);

create index event_overrides_ends_idx on public.event_overrides (ends_at);

alter table public.admins enable row level security;
alter table public.admin_log enable row level security;
alter table public.event_overrides enable row level security;
revoke all on public.admins, public.admin_log, public.event_overrides from anon, authenticated;
