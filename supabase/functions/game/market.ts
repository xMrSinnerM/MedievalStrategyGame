// The market: players trade wood, stone and food with each other, and gear
// and gems for Marks (the trade coin, server/rules/gear.ts). act()
// (game.ts) checks and pays for posting an offer and for buying one; index.ts
// keeps the offers in the market_offers table: an offer is "open" until a
// buyer takes it ("buying" while they pay, then "sold", then "paid" once the
// seller has the proceeds) or the seller cancels it ("cancelled", then
// "returned" once the goods are home); an open offer past its time goes
// straight back to the seller ("returned").

import type { CastleState } from "../../../server/rules/castle_state.ts";
import { addMarks, gemCount, type GearRules, type Item } from "../../../server/rules/gear.ts";
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
  /** Gear and gems for Marks. */
  items?: ItemMarketRules;
}

/**
 * Gear and gems at the market, always for Marks: an offer gives "gear:<rarity>"
 * (one piece, kept in the offer's `item`) or a gem ("ruby:3", up to gem_lot
 * of them), and wants "marks". Prices: gear_price by rarity, gem_price per
 * gem by tier ([lowest, highest]). A player has at most max_offers of these
 * up, besides their resource offers.
 */
export interface ItemMarketRules {
  max_offers: number;
  gem_lot: number;
  gear_price: Record<string, [number, number]>;
  gem_price: [number, number][];
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
  /** The piece of gear a "gear:<rarity>" offer gives. */
  item?: Item | null;
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
  /** The name of the gear an offer gave. */
  item_name?: string;
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

// --- Gear and gems for Marks ------------------------------------------------------------

export const MARKS = "marks";

/** Whether an offer gives gear or gems (and wants Marks). */
export function isItemGood(good: unknown, gear: GearRules): boolean {
  return typeof good === "string" && (good.startsWith("gear:") || gear.gemParts(good) !== undefined);
}

/** The price range for an offer giving `give_amount` of `give` (gear or a gem), or undefined. */
export function itemPriceRange(rules: ItemMarketRules, gear: GearRules, give: string, giveAmount: number): [number, number] | undefined {
  if (give.startsWith("gear:")) return rules.gear_price[give.slice(5)];
  const p = gear.gemParts(give);
  const per = p ? rules.gem_price[p.tier - 1] : undefined;
  return per ? [per[0] * giveAmount, per[1] * giveAmount] : undefined;
}

/**
 * Why this castle can't put up the gear or gem offer asked for ("" if it
 * can): `req.item` names the gear in the bag, or `req.give` the gem with
 * `req.give_amount` of them; `req.want_amount` is the price in Marks. `open`
 * is how many gear and gem offers it has up now.
 */
export function checkItemOffer(castle: CastleState, rules: MarketRules, gear: GearRules, req: Record<string, unknown>, open: number): string {
  const r = rules.items;
  if (r === undefined) return "Unknown order.";
  if (castle.keepLevel() < rules.unlock_keep) return `The market opens at keep level ${rules.unlock_keep}.`;
  const { give, give_amount, want, want_amount } = req;
  if (want !== MARKS) return "Gear and gems sell for Marks.";
  let good: string;
  let amount: number;
  if (give === "gear") {
    const item = castle.armoury.bag.find((x) => x.id === req.item);
    if (item === undefined) return "There's no such item in your bag.";
    good = `gear:${item.rarity}`;
    amount = 1;
  } else {
    if (gear.gemParts(give) === undefined) return "Choose what to sell.";
    if (!isAmount(give_amount)) return "Choose how many.";
    if (give_amount > r.gem_lot) return `One offer sells at most ${r.gem_lot} gems.`;
    if (give_amount > gemCount(castle, give as string)) return `You have only ${gemCount(castle, give as string)} of those gems.`;
    good = give as string;
    amount = give_amount;
  }
  if (!isAmount(want_amount)) return "Choose a price.";
  const range = itemPriceRange(r, gear, good, amount);
  if (range === undefined) return "That can't be sold here.";
  if (want_amount < range[0] || want_amount > range[1]) return `Ask between ${range[0]} and ${range[1]} Marks for it.`;
  if (open >= r.max_offers) return `You can have at most ${r.max_offers} gear and gem offers up at once.`;
  return "";
}

/** Takes what a checked gear or gem offer sells out of the castle: the offer's give, give_amount and item. */
export function takeItemOffer(castle: CastleState, req: Record<string, unknown>): { give: string; give_amount: number; item: Item | null } {
  if (req.give === "gear") {
    const i = castle.armoury.bag.findIndex((x) => x.id === req.item);
    const [item] = castle.armoury.bag.splice(i, 1);
    return { give: `gear:${item.rarity}`, give_amount: 1, item };
  }
  const key = req.give as string;
  const n = req.give_amount as number;
  giveGems(castle, key, -n);
  return { give: key, give_amount: n, item: null };
}

/** Why this castle can't buy a gear or gem offer ("" if it can), at time `now`. */
export function checkItemBuy(castle: CastleState, rules: MarketRules, gear: GearRules, offer: Offer | undefined, buyer: string,
  now: number): string {
  if (offer === undefined || offer.expires <= now) return "That offer is gone.";
  if (offer.seller_name === buyer) return "That's your own offer.";
  if (castle.keepLevel() < rules.unlock_keep) return `The market opens at keep level ${rules.unlock_keep}.`;
  if (castle.armoury.marks < offer.want_amount) return "You don't have enough Marks.";
  if (offer.give.startsWith("gear:") && castle.armoury.bag.length >= gear.bagSize) return "Your gear bag is full.";
  return "";
}

/** Puts what a gear or gem offer gives in the castle: gear in the bag (with a new id, even past a full bag), gems in the pouch. */
export function receiveItem(castle: CastleState, offer: Pick<Offer, "give" | "give_amount" | "item">): void {
  if (offer.give.startsWith("gear:")) {
    if (!offer.item) return;
    const a = castle.armoury;
    a.bag.push({ ...structuredClone(offer.item), id: a.next_item, gems: [...(offer.item.gems ?? [])] });
    a.next_item += 1;
  } else giveGems(castle, offer.give, offer.give_amount);
}

/** Marks and gems from the market (income keys "marks" and gem keys) and returned gear reach the castle. */
export function receiveArmoury(castle: CastleState, gear: GearRules, income: Dict, items: Item[]): void {
  for (const [k, n] of Object.entries(income)) {
    if (k === MARKS) addMarks(castle, n);
    else if (gear.gemParts(k) !== undefined) giveGems(castle, k, n);
  }
  for (const item of items) receiveItem(castle, { give: `gear:${item.rarity}`, give_amount: 1, item });
}

function giveGems(castle: CastleState, key: string, n: number): void {
  const have = gemCount(castle, key) + n;
  if (have > 0) castle.armoury.gems[key] = have;
  else delete castle.armoury.gems[key];
}
