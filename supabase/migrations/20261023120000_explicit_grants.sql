-- Explicit grants for every game table. From 2026-10-30 Supabase no longer
-- grants Data API access to new tables in "public" by default, so a fresh
-- database (a new project, a preview branch, `supabase db reset`) would
-- create these tables with no grants and the game server could not reach
-- them. The live database already has these grants; this changes nothing
-- there.
--
-- The game server (supabase/functions/game) reads and writes everything
-- with the service role. Players read only their own row and reports
-- directly (the policies in 20261011020717_game_server.sql); every other
-- table stays closed to anon and authenticated, as the earlier migrations
-- set it up. New tables: add the same grants in the migration that creates
-- them.

grant select, insert, update, delete on
  public.players, public.reports, public.raids, public.alliances, public.alliance_pending,
  public.chat_messages, public.aid, public.admins, public.admin_log, public.event_overrides
  to service_role;
grant select on public.alliance_summaries to service_role;
grant usage, select on all sequences in schema public to service_role;

grant select on public.players, public.reports to authenticated;
