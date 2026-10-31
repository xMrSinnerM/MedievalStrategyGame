-- Player mail and the reports inbox (supabase/functions/game/mail.ts).
-- Every letter is a row in one mailbox: sending puts a copy in the sender's
-- "sent" folder and one in each receiver's "inbox", so each side reads and
-- deletes their own. Only the game server reads or writes them, like the
-- other game tables. Reports get a read mark; the ones from before mail
-- count as read.

create table public.mail (
  id bigint generated always as identity primary key,
  owner uuid not null references public.players (user_id) on delete cascade,
  sender uuid references public.players (user_id) on delete set null,
  folder text not null,
  from_name text not null,
  to_name text not null,
  subject text not null,
  text text not null,
  at double precision not null,
  read boolean not null default false,
  constraint mail_folder check (folder in ('inbox', 'sent')),
  constraint mail_subject_length check (char_length(subject) between 1 and 60),
  constraint mail_text_length check (char_length(text) between 1 and 1000)
);

create index mail_owner_idx on public.mail (owner, folder, id desc);
create index mail_unread_idx on public.mail (owner) where folder = 'inbox' and not read;
create index mail_at_idx on public.mail (at);

alter table public.mail enable row level security;
revoke all on public.mail from anon, authenticated;
grant select, insert, update, delete on public.mail to service_role;
grant usage, select on all sequences in schema public to service_role;

alter table public.reports add column if not exists read boolean not null default true;
alter table public.reports alter column read set default false;
create index if not exists reports_unread_idx on public.reports (user_id) where not read;
