-- Phase 9: chat. Messages to the world channel have no alliance; messages to
-- an alliance go when it is disbanded. Only the game server reads or writes
-- them, like the other game tables.

create table public.chat_messages (
  id bigint generated always as identity primary key,
  alliance_id bigint references public.alliances (id) on delete cascade,
  user_id uuid not null references public.players (user_id) on delete cascade,
  name text not null,
  tag text not null default '',
  text text not null,
  at double precision not null,
  constraint chat_messages_text_length check (char_length(text) between 1 and 200)
);

create index chat_messages_alliance_idx on public.chat_messages (alliance_id, id);
create index chat_messages_user_idx on public.chat_messages (user_id, id);
create index chat_messages_at_idx on public.chat_messages (at);

alter table public.chat_messages enable row level security;
revoke all on public.chat_messages from anon, authenticated;
