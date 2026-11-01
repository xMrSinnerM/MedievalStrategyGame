-- Gear and gems at the market, for Marks (data/market.json `items`,
-- supabase/functions/game/market.ts): an offer giving "gear:<rarity>" keeps
-- the piece of gear it sells here; gem and resource offers leave it null.
-- The table's grants (service_role only) are unchanged.

alter table public.market_offers add column if not exists item jsonb;
