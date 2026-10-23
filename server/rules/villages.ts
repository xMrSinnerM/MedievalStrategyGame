// Resource villages: hamlets on the map that each work one resource. Local
// militia holds a village until someone beats them; then it sends its yield
// to its owner's castle, and online other players can take it from them. A
// port of scripts/economy/village_rules.gd; the numbers are in
// data/villages.json, where the villages stand in server/world/world.json.

import { carried } from "./baron_camp.ts";
import type { BaronRules } from "./baron_rules.ts";
import { autoWaves, DEFAULT_LAYOUT, siege, survivors, wallFromDefense, type SiegeResult, type Tools, type Wave } from "./battle.ts";
import type { BuildingRules } from "./building_rules.ts";
import { round, type Dict } from "./util.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

/** A village as the map has it (server/world/world.json). */
export interface VillageInfo {
  id: string;
  name: string;
  position: [number, number];
  level: number;
  /** The resource it works. */
  resource: string;
}

/** Who holds a village and since when (the villages table online). */
export interface VillageState {
  id: string;
  /** The owner's name; "" while the militia holds it. */
  owner: string;
  /** Soldiers the owner stationed there. */
  guard: Dict;
  /** When it last changed hands; its peace runs from here. */
  taken_at: number;
  /** Up to when its yield has gone to the owner. */
  paid_at: number;
}

export interface VillageFight extends SiegeResult {
  /** The attackers going home. */
  survivors: Dict;
  /** The defenders still standing. */
  guardLeft: Dict;
  /** What the attackers carry off from the village's store (empty unless they won). */
  loot: Dict;
}

export class VillageRules {
  yields: Dict;
  yieldGrowth: number;
  storeHours: number;
  guardBase: number;
  guardGrowth: number;
  guardArmies: { from_level: number; mix: Dict }[];
  palisadeBase: number;
  palisadePerLevel: number;
  slots: { keep: number; count: number }[];
  peaceHours: number;

  constructor(data: Json = {}) {
    this.yields = data.yields ?? {};
    this.yieldGrowth = Number(data.yield_growth ?? 1);
    this.storeHours = Number(data.store_hours ?? 0);
    this.guardBase = Number(data.guard_base ?? 0);
    this.guardGrowth = Number(data.guard_growth ?? 1);
    this.guardArmies = data.guard_armies ?? [];
    this.palisadeBase = Number(data.palisade_base ?? 0);
    this.palisadePerLevel = Number(data.palisade_per_level ?? 0);
    this.slots = data.slots ?? [];
    this.peaceHours = Number(data.peace_hours ?? 0);
  }

  /** What a village of this resource and level sends its owner each hour. */
  yieldPerHour(resource: string, level: number): number {
    return round(Number(this.yields[resource] ?? 0) * Math.pow(this.yieldGrowth, level - 1));
  }

  /** The most a village holds before its owner's castle gets it. */
  storeCap(resource: string, level: number): number {
    return this.yieldPerHour(resource, level) * this.storeHours;
  }

  /** What the village holds at time `t`: its full store under the militia, else its yield since it was last paid. */
  stock(info: VillageInfo, state: VillageState, t: number): number {
    const cap = this.storeCap(info.resource, info.level);
    if (state.owner === "") return cap;
    return Math.floor(Math.min(cap, this.yieldPerHour(info.resource, info.level) * Math.max(0, t - state.paid_at) / 3600));
  }

  /**
   * What an owned village sends its owner at time `t`, and up to when that
   * pays it (whole units only: the rest waits for the next time). A full
   * store sends everything it holds.
   */
  collect(info: VillageInfo, state: VillageState, t: number): { amount: number; paid_at: number } {
    const perHour = this.yieldPerHour(info.resource, info.level);
    if (state.owner === "" || perHour <= 0 || t <= state.paid_at) return { amount: 0, paid_at: state.paid_at };
    const made = perHour * (t - state.paid_at) / 3600;
    const cap = this.storeCap(info.resource, info.level);
    if (made >= cap) return { amount: cap, paid_at: t };
    const amount = Math.floor(made);
    return { amount, paid_at: state.paid_at + amount * 3600 / perHour };
  }

  /** The militia holding a village of this level (unit -> count). */
  militia(level: number): Dict {
    const all = round(this.guardBase * Math.pow(this.guardGrowth, level - 1));
    let mix: Dict = {};
    for (const army of this.guardArmies) if (level >= Number(army.from_level)) mix = army.mix;
    const out: Dict = {};
    let placed = 0;
    const units = Object.keys(mix);
    units.forEach((unit, i) => {
      const n = i < units.length - 1 ? round(all * Number(mix[unit])) : all - placed;
      if (n > 0) {
        out[unit] = n;
        placed += n;
      }
    });
    return out;
  }

  palisade(level: number): number {
    return this.palisadeBase + this.palisadePerLevel * (level - 1);
  }

  /** Who defends the village: the militia, or the soldiers its owner stationed there. */
  defenders(info: VillageInfo, state: VillageState): Dict {
    return state.owner === "" ? this.militia(info.level) : { ...state.guard };
  }

  /** How many villages a castle with this keep level may hold. */
  slotsFor(keep: number): number {
    let n = 0;
    for (const s of this.slots) if (keep >= Number(s.keep)) n = Number(s.count);
    return n;
  }

  /** The keep level that holds a first village. */
  firstSlotKeep(): number {
    return this.slots.length > 0 ? Number(this.slots[0].keep) : 99;
  }

  /** Until when a village that just changed hands can't be attacked. */
  peaceUntil(state: VillageState): number {
    return state.owner !== "" && state.taken_at > 0 ? state.taken_at + this.peaceHours * 3600 : 0;
  }

  /** Why you can't hold one more village ("" if you can). */
  checkRoom(keep: number, held: number): string {
    if (held < this.slotsFor(keep)) return "";
    if (keep < this.firstSlotKeep()) return `Your keep must reach level ${this.firstSlotKeep()} to hold a village.`;
    return "Your keep can't hold another village yet.";
  }

  /**
   * Storms the village's palisade with `waves` (by default the army in one
   * wave) and the attackers' siege `tools`, against its defenders in
   * DEFAULT_LAYOUT. A win carries off what the village holds, as much as the
   * survivors can carry (`lead` is the commander's gear, as for camps). The
   * village itself is not changed: capture() hands it over.
   */
  attack(units: BuildingRules, barons: BaronRules, info: VillageInfo, state: VillageState, army: Dict, seed: number, t: number,
    waves?: Wave[], tools: Tools = {}, lead: Dict = {}): VillageFight {
    const result = siege(units, waves ?? autoWaves(army), this.defenders(info, state), DEFAULT_LAYOUT, seed,
      wallFromDefense(this.palisade(info.level)), { a: tools, lead_a: lead });
    const out: VillageFight = { ...result, survivors: survivors(result.a), guardLeft: survivors(result.b), loot: {} };
    if (result.winner === "a") {
      out.loot = carried({ [info.resource]: this.stock(info, state, t) }, barons.carry(out.survivors) * (1 + (lead.loot ?? 0)));
    }
    return out;
  }
}

/** Hands a village to a new owner at time `t`, empty of soldiers, its peace starting. */
export function capture(state: VillageState, owner: string, t: number): VillageState {
  return { ...state, owner, guard: {}, taken_at: t, paid_at: t };
}

/** A village as nobody has touched it yet. */
export function untouched(id: string): VillageState {
  return { id, owner: "", guard: {}, taken_at: 0, paid_at: 0 };
}
