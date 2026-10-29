// The market: players trade wood, stone and food with each other. act()
// (game.ts) checks and pays for posting an offer and for buying one; index.ts
// keeps the offers in the market_offers table: an offer is "open" until a
// buyer takes it ("buying" while they pay, then "sold", then "paid" once the
// seller has the proceeds) or the seller cancels it ("cancelled", then
// "returned" once the goods are home); an open offer past its time goes
// straight back to the seller ("returned").

import type { CastleState } from "../../../server/rules/castle_state.ts";
import type { Dict } from "../../../server/rules/util.ts";

/** The market's numbers, from data/market.json. */
export interface MarketRules {
  goods: string[];
  unlock_keep: number;
  lot_per_keep_level: number;
  max_offers: number;
  min_rate: number;
  max_rate: number;
  fee: number;
  offer_hours: number;
}

/** An offer at the market (a row of the market_offers table). */
export interface Offer {
  id: number;
  seller_name: string;
  give: string;
  give_amount: number;
  want: string;
  want_amount: number;
  /** What the seller gets when it sells: want_amount minus the market's cut. */
  proceeds: number;
  posted: number;
  expires: number;
}

/** What a seller or buyer gets told (a server report). */
export interface MarketReport {
  kind: "market";
  /** sold (your offer was bought), bought (you bought one), expired (no buyer came), spilled (storage full). */
  event: "sold" | "bought" | "expired" | "spilled";
  at: number;
  /** The other player. */
  name?: string;
  give?: string;
  give_amount?: number;
  want?: string;
  want_amount?: number;
  /** sold: what reaches the seller after the market's cut. */
  proceeds?: number;
  /** spilled: what the seller's storage couldn't hold. */
  lost?: Dict;
}

/** How much one offer can give from this castle. */
export function lotLimit(castle: CastleState, rules: MarketRules): number {
  return rules.lot_per_keep_level * Math.max(1, castle.keepLevel());
}

/** What the seller gets for an offer wanting this much. */
export function proceedsFor(rules: MarketRules, wantAmount: number): number {
  return wantAmount - Math.ceil(wantAmount * rules.fee);
}

function isAmount(n: unknown): n is number {
  return typeof n === "number" && Number.isInteger(n) && n > 0;
}

/** Why this castle can't post the offer asked for ("" if it can); `open` is how many offers it has up now. */
export function checkOffer(castle: CastleState, rules: MarketRules, req: Record<string, unknown>, open: number): string {
  if (castle.keepLevel() < rules.unlock_keep) return `The market opens at keep level ${rules.unlock_keep}.`;
  const { give, want, give_amount, want_amount } = req;
  if (typeof give !== "string" || !rules.goods.includes(give)) return "Choose what to give.";
  if (typeof want !== "string" || !rules.goods.includes(want)) return "Choose what you want for it.";
  if (give === want) return "Trade one good for another.";
  if (!isAmount(give_amount) || !isAmount(want_amount)) return "Choose how much.";
  if (give_amount > Math.floor(castle.resources[give] ?? 0)) return `You don't have that much ${give}.`;
  const cap = lotLimit(castle, rules);
  if (give_amount > cap) return `One offer gives at most ${cap}.`;
  const rate = want_amount / give_amount;
  if (rate < rules.min_rate - 1e-9 || rate > rules.max_rate + 1e-9) {
    return `Ask between ${rules.min_rate} and ${rules.max_rate} ${want} for each ${give}.`;
  }
  if (open >= rules.max_offers) return `You can have at most ${rules.max_offers} offers up at once.`;
  return "";
}

/** Why this castle can't buy the offer ("" if it can), at time `now`. */
export function checkBuy(castle: CastleState, rules: MarketRules, offer: Offer | undefined, buyer: string, now: number): string {
  if (offer === undefined || offer.expires <= now) return "That offer is gone.";
  if (offer.seller_name === buyer) return "That's your own offer.";
  if (castle.keepLevel() < rules.unlock_keep) return `The market opens at keep level ${rules.unlock_keep}.`;
  if (Math.floor(castle.resources[offer.want] ?? 0) < offer.want_amount) return `You don't have enough ${offer.want}.`;
  if ((castle.resources[offer.give] ?? 0) + offer.give_amount > castle.storageCapacity()) {
    return `Your storage has no room for ${offer.give_amount} more ${offer.give}.`;
  }
  return "";
}

/**
 * Proceeds and returned goods reach the seller's castle: what fits is
 * stored, the rest is lost. Returns what was lost.
 */
export function receive(castle: CastleState, income: Dict): Dict {
  const cap = castle.storageCapacity();
  const lost: Dict = {};
  for (const r of Object.keys(income)) {
    if (!(r in castle.resources) || income[r] <= 0) continue;
    const have = castle.resources[r];
    const room = Math.max(0, Math.floor(cap - have));
    const got = Math.min(room, income[r]);
    castle.resources[r] = have + got;
    if (got < income[r]) lost[r] = income[r] - got;
  }
  return lost;
}

/** The going rate from recent sales: for each "give>want", how much was asked per unit given on average. */
export function goingRates(sales: Pick<Offer, "give" | "give_amount" | "want" | "want_amount">[]): Dict {
  const sums: Record<string, { give: number; want: number }> = {};
  for (const s of sales) {
    const key = `${s.give}>${s.want}`;
    sums[key] ??= { give: 0, want: 0 };
    sums[key].give += s.give_amount;
    sums[key].want += s.want_amount;
  }
  const out: Dict = {};
  for (const [key, s] of Object.entries(sums)) if (s.give > 0) out[key] = Math.round((s.want / s.give) * 100) / 100;
  return out;
}
