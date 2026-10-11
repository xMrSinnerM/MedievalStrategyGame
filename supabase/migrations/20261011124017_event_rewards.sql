-- Baron Invasion rewards: how many of the invasion's reward tiers each player has claimed.
alter table public.players add column event_claimed integer not null default 0;
