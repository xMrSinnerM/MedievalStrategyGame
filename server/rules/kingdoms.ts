// The other kingdoms: lands across the sea, each with its own map, robber
// barons and a good found nowhere else (iron in Frostmark, glass in
// Sunreach). A port of scripts/economy/kingdom_rules.gd; the numbers are in
// data/kingdoms.json.

import type { CampData } from "./baron_camp.ts";
import { CastleState, type CastleData } from "./castle_state.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

export const CASTLE_PREFIX = "kingdom_";

/** A good on its way from a kingdom to your main castle. */
export interface Ship {
  id: number;
  good: string;
  amount: number;
  depart: number;
  arrive: number;
}

/** Your castle in one kingdom, as stored with you (players.kingdoms online). */
export interface KingdomData {
  castle: CastleData;
  ships: Ship[];
  next_ship: number;
}

export function castleId(kingdom: string): string {
  return CASTLE_PREFIX + kingdom;
}

/** The kingdom a castle id belongs to ("" for other castles). */
export function kingdomOf(id: unknown): string {
  return typeof id === "string" && id.startsWith(CASTLE_PREFIX) ? id.slice(CASTLE_PREFIX.length) : "";
}

export class KingdomRules {
  goods: Record<string, Json>;
  types: string[];
  keepCap: number;
  kingdoms: Record<string, Json>;

  constructor(data: Json = {}) {
    this.goods = data.goods ?? {};
    this.types = (data.types ?? []).map(String);
    this.keepCap = Number(data.keep_cap ?? 1);
    this.kingdoms = data.kingdoms ?? {};
  }

  has(kingdom: unknown): kingdom is string {
    return typeof kingdom === "string" && Object.hasOwn(this.kingdoms, kingdom);
  }

  goodName(good: string): string {
    return String(this.goods[good]?.name ?? good);
  }

  /** Why a castle can't be founded in this kingdom now ("" if it can). `founded` is the player's kingdoms. */
  checkFound(main: CastleState, founded: Record<string, unknown>, kingdom: unknown): string {
    if (!this.has(kingdom)) return "No such kingdom.";
    const k = this.kingdoms[kingdom];
    if (Object.hasOwn(founded, kingdom)) return `You already have a castle in ${k.name}.`;
    if (main.keepLevel() < Number(k.keep_needed)) return `Your keep must reach level ${Number(k.keep_needed)} first.`;
    if (!main.canAfford(k.cost)) return `Not enough resources to found a castle in ${k.name}.`;
    return "";
  }

  /** Pays for a castle in the kingdom from the main castle and returns it. */
  found(main: CastleState, kingdom: string, now: number): CastleState {
    const k = this.kingdoms[kingdom];
    for (const r of Object.keys(k.cost)) {
      main.resources[r] -= k.cost[r];
      main.stats.spent += k.cost[r];
    }
    const castle = CastleState.createNew(main.rules, castleId(kingdom), String(k.castle_name), "player", now);
    castle.limits = { types: [...this.types], keep: this.keepCap };
    castle.yields = { [String(k.good)]: { rate: Number(k.yield.rate), store: Number(k.yield.store) } };
    return castle;
  }

  /** The kingdom's robber baron camps as a new player finds them. */
  camps(kingdom: string): CampData[] {
    return (this.kingdoms[kingdom].camps ?? []).map((c: Json) => ({ id: String(c.id), name: String(c.name),
      position: [Number(c.position[0]), Number(c.position[1])] as [number, number], level: Number(c.level), defeats: 0, rebuilt_at: 0,
      kingdom }));
  }

  voyage(kingdom: string): number {
    return Number(this.kingdoms[kingdom].voyage ?? 0);
  }

  /** Whole units of the kingdom's good waiting at your castle there. */
  waiting(castle: CastleState, kingdom: string): number {
    return Math.floor((castle.goods[String(this.kingdoms[kingdom].good)] ?? 0) + 0.0001);
  }

  /** Why no ship can sail home from this kingdom now ("" if one can). */
  checkShip(castle: CastleState | null | undefined, kingdom: unknown): string {
    if (!this.has(kingdom) || !castle) return "You have no castle there.";
    if (this.waiting(castle, kingdom) < 1) return `There is no ${this.goodName(String(this.kingdoms[kingdom].good)).toLowerCase()} to ship yet.`;
    return "";
  }

  /** Loads everything waiting onto a ship for home and returns the ship. */
  ship(castle: CastleState, ships: Ship[], nextShip: number, kingdom: string, now: number): Ship {
    const good = String(this.kingdoms[kingdom].good);
    const amount = this.waiting(castle, kingdom);
    castle.goods[good] = (castle.goods[good] ?? 0) - amount;
    const boat: Ship = { id: nextShip, good, amount, depart: now, arrive: now + this.voyage(kingdom) };
    ships.push(boat);
    return boat;
  }
}

/** Unloads the ships that are in by `t` at your main castle. Returns the ships still at sea. */
export function deliverShips(home: CastleState, ships: Ship[], t: number): Ship[] {
  for (const boat of ships) {
    if (boat.arrive <= t) home.goods[boat.good] = (home.goods[boat.good] ?? 0) + boat.amount;
  }
  return ships.filter((boat) => boat.arrive > t);
}
