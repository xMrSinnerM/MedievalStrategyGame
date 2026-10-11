-- Phase 8: every player has their own spot on the map, and other players can
-- see each castle's name, spot and level (but nothing else) through the game
-- server's "world" order.

alter table public.players add column level integer not null default 1;

create unique index players_home_key on public.players (home_x, home_y);
