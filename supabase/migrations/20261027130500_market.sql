-- The market: offers players put up to trade wood, stone and food
-- (data/market.json, supabase/functions/game/market.ts). The goods wait in
-- the row while it is "open"; a buyer turns it "sold" (the seller's next
-- request takes the proceeds and makes it "paid"; it is "buying" while the
-- buyer's request pays for it), the seller can cancel it
-- ("cancelled", then "returned" once the goods are back), and an open offer
-- past `expires` goes back to the seller ("returned"). Only the game server
-- reads or writes it, like the other game tables.

create table public.market_offers (
  id bigint generated always as identity primary key,
  seller uuid not null references public.players (user_id) on delete cascade,
  seller_name text not null,
  give text not null,
  give_amount integer not null check (give_amount > 0),
  want text not null,
  want_amount integer not null check (want_amount > 0),
  proceeds integer not null check (proceeds >= 0),
  posted double precision not null,
  expires double precision not null,
  state text not null default 'open' check (state in ('open', 'buying', 'sold', 'paid', 'cancelled', 'returned')),
  buyer uuid references public.players (user_id) on delete set null,
  buyer_name text,
  sold_at double precision
);

create index market_offers_open_idx on public.market_offers (state, expires) where state = 'open';
create index market_offers_seller_idx on public.market_offers (seller, state);
create index market_offers_sold_idx on public.market_offers (sold_at desc) where sold_at is not null;

alter table public.market_offers enable row level security;
revoke all on public.market_offers from anon, authenticated;
grant select, insert, update, delete on public.market_offers to service_role;
grant usage, select on sequence public.market_offers_id_seq to service_role;
