// Commanders and gear: commanders lead your attacks and the castellan your
// defence, each wearing gear robber barons drop. A port of
// scripts/economy/gear_rules.gd; the numbers are in data/gear.json.
//
// Everything lives in the castle's `armoury` (see Armoury): the commanders,
// the castellan's gear, the bag of gear not worn, and the next item's id.

import type { CastleState } from "./castle_state.ts";
import { Rng } from "./rng.ts";
import type { Dict } from "./util.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

export type GearSide = "attack" | "defence";

export interface Item {
  id: number;
  slot: string;
  side: GearSide;
  rarity: string;
  name: string;
  /** Stat -> percent. */
  stats: Dict;
}

export interface Commander {
  id: number;
  name: string;
  level: number;
  xp: number;
  /** Slot -> the item worn there. */
  gear: Record<string, Item>;
  /** Unix time the commander's army is home again. */
  away_until: number;
}

export interface Armoury {
  commanders: Commander[];
  /** Slot -> the castellan's item there. */
  castellan: Record<string, Item>;
  bag: Item[];
  next_item: number;
}

/** A commander leading an army: what the fight needs and the report shows. */
export interface Lead {
  id: number;
  name: string;
  /** Stat -> share (0.12 for 12%), from effects(). */
  fx: Dict;
  /** Xp earned in the fight, once it is fought (raids keep it until the army is home). */
  xp?: number;
}

/** What a fight gave a commander, for the report. */
export interface LeadReport {
  id: number;
  name: string;
  xp: number;
  level: number;
  leveled: boolean;
}

export function newArmoury(): Armoury {
  return { commanders: [], castellan: {}, bag: [], next_item: 1 };
}

export class GearRules {
  slots: string[];
  slotNames: Dict<string>;
  stats: Record<string, Json>;
  slotStats: Record<string, Record<string, string[]>>;
  caps: Dict;
  rarities: Record<string, Json>;
  dropBase: number;
  dropPerLevel: number;
  dropMax: number;
  bagSize: number;
  commanderSlotTable: number[];
  perLevel: number;
  levels: number[];
  xpWinPerLevel: number;
  xpPlayerWin: number;
  xpLoss: number;
  commanderNames: string[];
  names: Json;

  constructor(data: Json = {}) {
    this.slots = (data.slots ?? []).map(String);
    this.slotNames = data.slot_names ?? {};
    this.stats = data.stats ?? {};
    this.slotStats = data.slot_stats ?? { attack: {}, defence: {} };
    this.caps = data.caps ?? {};
    this.rarities = data.rarities ?? {};
    this.dropBase = Number(data.drop_base ?? 0);
    this.dropPerLevel = Number(data.drop_per_level ?? 0);
    this.dropMax = Number(data.drop_max ?? 0);
    this.bagSize = Number(data.bag_size ?? 0);
    this.commanderSlotTable = (data.commander_slots ?? [0]).map(Number);
    this.perLevel = Number(data.per_level ?? 0);
    this.levels = (data.levels ?? [0]).map(Number);
    this.xpWinPerLevel = Number(data.xp_win_per_level ?? 0);
    this.xpPlayerWin = Number(data.xp_player_win ?? 0);
    this.xpLoss = Number(data.xp_loss ?? 0);
    this.commanderNames = (data.commander_names ?? []).map(String);
    this.names = data.names ?? {};
  }

  commanderSlots(keep: number): number {
    if (this.commanderSlotTable.length === 0 || keep < 1) return 0;
    return this.commanderSlotTable[Math.min(keep, this.commanderSlotTable.length) - 1];
  }

  maxLevel(): number {
    return this.levels.length;
  }

  /** The level `xp` reaches (1 .. maxLevel()). */
  levelFor(xp: number): number {
    let level = 0;
    for (const need of this.levels) if (xp >= need) level += 1;
    return Math.max(1, level);
  }

  /** Gives a castle as many commanders as its keep allows. */
  sync(castle: CastleState): void {
    const a = castle.armoury;
    const want = this.commanderSlots(castle.keepLevel());
    while (a.commanders.length < want) {
      const i = a.commanders.length;
      const base = this.commanderNames.length > 0 ? this.commanderNames[i % this.commanderNames.length] : "Commander";
      a.commanders.push({ id: i + 1, name: i < this.commanderNames.length ? base : `${base} the Younger`, level: 1, xp: 0, gear: {},
        away_until: 0 });
    }
  }

  /** What gear (and a commander's level) does in a fight: stat -> share, only the stats that are there. */
  effects(gear: Record<string, Item>, level = 1): Dict {
    const sum: Dict = {};
    for (const slot of this.slots) {
      const item = gear[slot];
      if (item === undefined) continue;
      for (const [stat, n] of Object.entries(item.stats)) sum[stat] = (sum[stat] ?? 0) + n;
    }
    if (level > 1 && this.perLevel > 0) {
      for (const stat of ["wall_attack", "yard_attack"]) sum[stat] = (sum[stat] ?? 0) + this.perLevel * (level - 1);
    }
    const out: Dict = {};
    for (const stat of Object.keys(this.stats)) {
      const n = Math.min(sum[stat] ?? 0, this.caps[stat] ?? 0);
      if (n > 0) out[stat] = n / 100;
    }
    return out;
  }

  castellanEffects(castle: CastleState): Dict {
    return this.effects(castle.armoury.castellan);
  }

  commander(castle: CastleState, id: unknown): Commander | undefined {
    return castle.armoury.commanders.find((c) => c.id === id);
  }

  /**
   * The commander to lead an army, or why not. No commander (`id` undefined,
   * null or 0) is fine: the result is then null.
   */
  checkLead(castle: CastleState, id: unknown, now: number): Lead | null | string {
    if (id === undefined || id === null || id === 0) return null;
    const c = this.commander(castle, id);
    if (c === undefined) return "No such commander.";
    if (c.away_until > now) return `${c.name} is still away with an army.`;
    return { id: c.id, name: c.name, fx: this.effects(c.gear, c.level) };
  }

  /** Gives a commander xp; returns the report line for it. */
  addXp(castle: CastleState, id: number, xp: number): LeadReport | undefined {
    const c = this.commander(castle, id);
    if (c === undefined) return undefined;
    const before = c.level;
    c.xp += xp;
    c.level = this.levelFor(c.xp);
    return { id: c.id, name: c.name, xp, level: c.level, leveled: c.level > before };
  }

  dropChance(level: number): number {
    return Math.min(this.dropBase + this.dropPerLevel * (level - 1), this.dropMax);
  }

  rarityWeight(rarity: string, level: number): number {
    const w = this.rarities[rarity].weight;
    return Math.max(0, Number(w[0]) + Number(w[1]) * (level - 1));
  }

  /** What a beaten camp of `level` drops (no id yet), or null. The same seed gives the same item. */
  rollDrop(level: number, seed: number): Item | null {
    if (this.slots.length === 0) return null;
    const rng = new Rng(seed);
    if (rng.randf() >= this.dropChance(level)) return null;
    const kinds = Object.keys(this.rarities);
    let total = 0;
    for (const r of kinds) total += this.rarityWeight(r, level);
    let pick = rng.randf() * total;
    let rarity = kinds[kinds.length - 1];
    for (const r of kinds) {
      const w = this.rarityWeight(r, level);
      if (pick < w) {
        rarity = r;
        break;
      }
      pick -= w;
    }
    const side: GearSide = rng.randi() % 2 === 0 ? "attack" : "defence";
    const slot = this.slots[rng.randi() % this.slots.length];
    const def = this.rarities[rarity];
    const pool = [...this.slotStats[side][slot]];
    const stats: Dict = {};
    const [lo, hi] = [Number(def.range[0]), Number(def.range[1])];
    for (let k = 0; k < Number(def.stats) && pool.length > 0; k++) {
      const stat = pool.splice(rng.randi() % pool.length, 1)[0];
      stats[stat] = lo + rng.randi() % (hi - lo + 1);
    }
    let name: string;
    if (rarity === "legendary") {
      const list: string[] = this.names.legendary[side][slot];
      name = list[rng.randi() % list.length];
    } else {
      const adjectives: string[] = this.names.adjectives[rarity];
      const nouns: string[] = this.names.nouns[side][slot];
      const adjective = adjectives[rng.randi() % adjectives.length];
      name = `${adjective} ${nouns[rng.randi() % nouns.length]}`;
    }
    return { id: 0, slot, side, rarity, name, stats };
  }

  /** Puts an item in the bag with a new id; false when the bag is full. */
  give(castle: CastleState, item: Item): boolean {
    const a = castle.armoury;
    if (a.bag.length >= this.bagSize) return false;
    item.id = a.next_item;
    a.next_item += 1;
    a.bag.push(item);
    return true;
  }

  sellPrice(item: Item): number {
    return Number(this.rarities[item.rarity]?.sell ?? 0);
  }

  /** Sells an item from the bag for gold (in full, even past the storage cap). */
  sell(castle: CastleState, itemId: unknown): string {
    const bag = castle.armoury.bag;
    const i = bag.findIndex((x) => x.id === itemId);
    if (i < 0) return "There's no such item in your bag.";
    const [item] = bag.splice(i, 1);
    castle.resources.gold = (castle.resources.gold ?? 0) + this.sellPrice(item);
    return "";
  }

  /** The gear a commander (an id) or the castellan ("castellan") wears, or why it can't be changed now. */
  private wearer(castle: CastleState, who: unknown, now: number): { gear: Record<string, Item>; side: GearSide } | string {
    if (who === "castellan") return { gear: castle.armoury.castellan, side: "defence" };
    const c = this.commander(castle, who);
    if (c === undefined) return "No such commander.";
    if (c.away_until > now) return `${c.name} is away with an army.`;
    return { gear: c.gear, side: "attack" };
  }

  /** Puts an item from the bag on a commander or the castellan, swapping out what was worn there. */
  equip(castle: CastleState, who: unknown, itemId: unknown, now: number): string {
    const w = this.wearer(castle, who, now);
    if (typeof w === "string") return w;
    const bag = castle.armoury.bag;
    const i = bag.findIndex((x) => x.id === itemId);
    if (i < 0) return "There's no such item in your bag.";
    const item = bag[i];
    if (item.side !== w.side) return w.side === "attack" ? "Commanders wear attack gear." : "The castellan wears defence gear.";
    bag.splice(i, 1);
    const old = w.gear[item.slot];
    if (old !== undefined) bag.push(old);
    w.gear[item.slot] = item;
    return "";
  }

  /** Takes an item off a commander or the castellan and puts it in the bag. */
  unequip(castle: CastleState, who: unknown, slot: unknown, now: number): string {
    const w = this.wearer(castle, who, now);
    if (typeof w === "string") return w;
    const item = typeof slot === "string" ? w.gear[slot] : undefined;
    if (item === undefined) return "Nothing is worn there.";
    if (castle.armoury.bag.length >= this.bagSize) return "Your bag is full.";
    delete w.gear[slot as string];
    castle.armoury.bag.push(item);
    return "";
  }
}

/** A clean armoury from saved data (anything malformed is dropped). */
// deno-lint-ignore no-explicit-any
export function readArmoury(data: any): Armoury {
  const a = newArmoury();
  if (data === null || typeof data !== "object") return a;
  const item = (x: Json): Item | undefined => {
    if (x === null || typeof x !== "object") return undefined;
    const stats: Dict = {};
    for (const k of Object.keys(x.stats ?? {})) stats[k] = Math.trunc(Number(x.stats[k]));
    return { id: Math.trunc(Number(x.id ?? 0)), slot: String(x.slot ?? ""), side: x.side === "defence" ? "defence" : "attack",
      rarity: String(x.rarity ?? "common"), name: String(x.name ?? ""), stats };
  };
  const gear = (g: Json): Record<string, Item> => {
    const out: Record<string, Item> = {};
    for (const slot of Object.keys(g ?? {})) {
      const it = item(g[slot]);
      if (it !== undefined) out[slot] = it;
    }
    return out;
  };
  for (const c of Array.isArray(data.commanders) ? data.commanders : []) {
    a.commanders.push({ id: Math.trunc(Number(c.id ?? 0)), name: String(c.name ?? ""), level: Math.trunc(Number(c.level ?? 1)),
      xp: Math.trunc(Number(c.xp ?? 0)), gear: gear(c.gear), away_until: Number(c.away_until ?? 0) });
  }
  a.castellan = gear(data.castellan);
  for (const x of Array.isArray(data.bag) ? data.bag : []) {
    const it = item(x);
    if (it !== undefined) a.bag.push(it);
  }
  a.next_item = Math.trunc(Number(data.next_item ?? 1));
  return a;
}
