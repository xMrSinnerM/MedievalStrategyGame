// Outposts: a second castle with its own buildings, storage and production,
// working a region that boosts one resource, and carts that carry resources
// between it and your home. A port of scripts/economy/outpost_rules.gd; the
// numbers are in data/outposts.json.

import { CastleState, type CastleData } from "./castle_state.ts";
import type { Dict } from "./util.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

export const OUTPOST_ID = "outpost";

/** Resources on their way between your castles. */
export interface Cart {
  id: number;
  /** Where they are going: your main castle or the outpost. */
  to: "home" | "outpost";
  resources: Dict;
  depart: number;
  arrive: number;
}

/** Your outpost, as stored with you (players.outpost online). */
export interface OutpostData {
  name: string;
  region: string;
  x: number;
  y: number;
  castle: CastleData;
  carts: Cart[];
  next_cart: number;
}

export class OutpostRules {
  keepNeeded: number;
  cost: Dict;
  keepCap: number;
  types: string[];
  cartShare: number;
  cartMin: number;
  regions: Record<string, Json>;

  constructor(data: Json = {}) {
    this.keepNeeded = Number(data.keep_needed ?? 99);
    this.cost = data.cost ?? {};
    this.keepCap = Number(data.keep_cap ?? 1);
    this.types = (data.types ?? []).map(String);
    this.cartShare = Number(data.cart_share ?? 0);
    this.cartMin = Number(data.cart_min ?? 0);
    this.regions = data.regions ?? {};
  }

  /** Why an outpost can't be founded now ("" if it can). `spot` is where it would stand, or null. */
  checkFound(main: CastleState, has: boolean, region: unknown, spot: unknown): string {
    if (has) return "You already have an outpost.";
    if (main.keepLevel() < this.keepNeeded) return `Your keep must reach level ${this.keepNeeded} first.`;
    if (typeof region !== "string" || !Object.hasOwn(this.regions, region)) return "Choose a region for your outpost.";
    if (spot === null || spot === undefined) return "There's no free land for an outpost.";
    if (!main.canAfford(this.cost)) return "Not enough resources to found an outpost.";
    return "";
  }

  /** Pays for an outpost from the main castle and returns its new castle. */
  found(main: CastleState, region: string, now: number): CastleState {
    for (const r of Object.keys(this.cost)) {
      main.resources[r] -= this.cost[r];
      main.stats.spent += this.cost[r];
    }
    const outpost = CastleState.createNew(main.rules, OUTPOST_ID, String(this.regions[region].name), "player", now);
    outpost.boost = { [region]: Number(this.regions[region].bonus) };
    outpost.limits = { types: [...this.types], keep: this.keepCap };
    return outpost;
  }

  /** How much one trip of carts from this castle can carry. */
  cartCapacity(from: CastleState): number {
    return Math.max(this.cartMin, Math.floor(from.storageCapacity() * this.cartShare));
  }

  /** Why these resources can't leave `from` by cart ("" if they can). */
  checkCarts(from: CastleState, resources: unknown): string {
    if (resources === null || typeof resources !== "object" || Array.isArray(resources)) return "Bad resources.";
    let total = 0;
    for (const [r, n] of Object.entries(resources as Record<string, unknown>)) {
      if (!from.rules.resources.includes(r)) return "Bad resources.";
      if (typeof n !== "number" || !Number.isInteger(n) || n < 0) return "Bad resources.";
      if (n > Math.floor(from.resources[r] ?? 0)) return "Not enough resources.";
      total += n;
    }
    if (total <= 0) return "Load something onto the carts.";
    const cap = this.cartCapacity(from);
    if (total > cap) return `Carts carry at most ${cap} per trip.`;
    return "";
  }
}

/** Unloads carts into a castle, up to its storage (what doesn't fit is lost). */
export function unload(to: CastleState, resources: Dict): void {
  const cap = to.storageCapacity();
  for (const r of Object.keys(resources)) {
    if (!(r in to.resources)) continue;
    const have = to.resources[r];
    to.resources[r] = Math.max(have, Math.min(cap, have + resources[r]));
  }
}

/**
 * Delivers the carts due by `t`, in order, running each castle up to the
 * moment they arrive. Returns the carts still on the road.
 */
export function deliverCarts(home: CastleState, outpost: CastleState, carts: Cart[], t: number): Cart[] {
  const due = carts.filter((c) => c.arrive <= t).sort((a, b) => a.arrive - b.arrive || a.id - b.id);
  for (const c of due) {
    const to = c.to === "home" ? home : outpost;
    to.advanceTo(c.arrive);
    unload(to, c.resources);
  }
  return carts.filter((c) => c.arrive > t);
}

/** The free castle spot nearest `home` (not home itself), or null. */
export function nearestSpot(spots: [number, number][], home: [number, number], taken: [number, number][]): [number, number] | null {
  const used = new Set(taken.map(([x, y]) => `${x},${y}`));
  let best: [number, number] | null = null;
  let bestD = Infinity;
  for (const s of spots) {
    if (used.has(`${s[0]},${s[1]}`) || (s[0] === home[0] && s[1] === home[1])) continue;
    const d = Math.hypot(s[0] - home[0], s[1] - home[1]);
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}
