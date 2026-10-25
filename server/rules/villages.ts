// Resource villages: hamlets on the map that each work one resource. Local
// militia holds a village until someone beats them; then it sends its yield
// to its owner's castle, and online other players can take it from them. A
// port of scripts/economy/village_rules.gd; the numbers are in
// data/villages.json, where the villages stand in server/world/world.json.
// Capitals (the towns, data/capitals.json) are villages with a stronger
// guard that also raise their holder's alliance's production: CapitalRules,
// a port of scripts/economy/capital_rules.gd. Whoever holds a capital can
// raise town buildings there (walls, market, guardhouse, guild hall), one at
// a time; they stay with the town when it changes hands.

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
  /** A capital (one of the towns), with CapitalRules. */
  capital?: boolean;
  /** For a capital: the faction whose town it is. */
  faction?: string;
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
  /** A capital's town buildings (building -> level). */
  buildings?: Dict;
  /** A capital's town building under way, if any. */
  building?: TownBuild | null;
}

/** A town building going up in a capital. */
export interface TownBuild {
  id: string;
  /** The level it reaches. */
  level: number;
  finish: number;
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

  /** What the village sends its holder each hour now (a capital's market adds to it). */
  rate(info: VillageInfo, _state: VillageState, _t: number): number {
    return this.yieldPerHour(info.resource, info.level);
  }

  /** The most the village holds now. */
  cap(info: VillageInfo, state: VillageState, t: number): number {
    return round(this.rate(info, state, t) * this.storeHours);
  }

  /** What the village holds at time `t`: its full store under the militia, else its yield since it was last paid. */
  stock(info: VillageInfo, state: VillageState, t: number): number {
    const most = this.cap(info, state, t);
    if (state.owner === "") return most;
    return Math.floor(Math.min(most, this.rate(info, state, t) * Math.max(0, t - state.paid_at) / 3600));
  }

  /**
   * What an owned village sends its owner at time `t`, and up to when that
   * pays it (whole units only: the rest waits for the next time). A full
   * store sends everything it holds.
   */
  collect(info: VillageInfo, state: VillageState, t: number): { amount: number; paid_at: number } {
    const perHour = this.rate(info, state, t);
    if (state.owner === "" || perHour <= 0 || t <= state.paid_at) return { amount: 0, paid_at: state.paid_at };
    const made = perHour * (t - state.paid_at) / 3600;
    const most = this.cap(info, state, t);
    if (made >= most) return { amount: most, paid_at: t };
    const amount = Math.floor(made);
    return { amount, paid_at: state.paid_at + amount * 3600 / perHour };
  }

  /** The militia holding a village of this level (unit -> count). */
  militia(level: number): Dict {
    return this.mix(round(this.guardBase * Math.pow(this.guardGrowth, level - 1)), level);
  }

  /** `all` soldiers in the militia's mix for this level. */
  protected mix(all: number, level: number): Dict {
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

  /** How strong the village's walls are now (a capital's town walls add to them). */
  wallDefense(info: VillageInfo, _state: VillageState, _t: number): number {
    return this.palisade(info.level);
  }

  /** Who defends the village: the militia, or the soldiers its owner stationed there. */
  defenders(info: VillageInfo, state: VillageState, _t = 0): Dict {
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
    const result = siege(units, waves ?? autoWaves(army), this.defenders(info, state, t), DEFAULT_LAYOUT, seed,
      wallFromDefense(this.wallDefense(info, state, t)), { a: tools, lead_a: lead });
    const out: VillageFight = { ...result, survivors: survivors(result.a), guardLeft: survivors(result.b), loot: {} };
    if (result.winner === "a") {
      out.loot = carried({ [info.resource]: this.stock(info, state, t) }, barons.carry(out.survivors) * (1 + (lead.loot ?? 0)));
    }
    return out;
  }
}

/**
 * Hands a village to a new owner at time `t`, empty of soldiers, its peace
 * starting. A capital keeps its town buildings; one still being built is lost.
 */
export function capture(state: VillageState, owner: string, t: number): VillageState {
  return { ...settled(state, t), owner, guard: {}, taken_at: t, paid_at: t };
}

/** The state with a town building finished by `t` counted in and one still under way dropped (for a change of hands). */
export function settled(state: VillageState, t: number): VillageState {
  const { building, ...out } = state;
  const levels: Dict = { ...(state.buildings ?? {}) };
  if (building && building.finish <= t) levels[building.id] = building.level;
  if (Object.keys(levels).length > 0) out.buildings = levels;
  return out;
}

/** A village as nobody has touched it yet. */
export function untouched(id: string): VillageState {
  return { id, owner: "", guard: {}, taken_at: 0, paid_at: 0 };
}

/** Capitals: towns that work like villages, with their own numbers, room and production bonus. */
export class CapitalRules extends VillageRules {
  minKeep: number;
  perPlayer: number;
  perAlliance: number;
  bonusBase: number;
  bonusPerLevel: number;
  maxBonus: number;
  /** Town buildings: id -> {name, max_level, cost, cost_growth, time, time_growth, and its effect}. */
  buildings: Record<string, Json>;
  guildMax: number;

  constructor(data: Json = {}) {
    super(data);
    this.buildings = data.buildings ?? {};
    this.guildMax = Number(data.guild_max ?? 0);
    this.minKeep = Number(data.min_keep ?? 4);
    this.perPlayer = Number(data.per_player ?? 1);
    this.perAlliance = Number(data.per_alliance ?? 3);
    this.bonusBase = Number(data.bonus_base ?? 0);
    this.bonusPerLevel = Number(data.bonus_per_level ?? 0);
    this.maxBonus = Number(data.max_bonus ?? 0);
  }

  override slotsFor(keep: number): number {
    return keep >= this.minKeep ? this.perPlayer : 0;
  }

  override firstSlotKeep(): number {
    return this.minKeep;
  }

  /** Why you can't hold one more capital ("" if you can). */
  override checkRoom(keep: number, held: number): string {
    if (keep < this.minKeep) return `Your keep must reach level ${this.minKeep} to take a capital.`;
    if (held >= this.perPlayer) return this.perPlayer === 1 ? "You already hold a capital." : `You already hold ${this.perPlayer} capitals.`;
    return "";
  }

  /** Why your alliance can't hold one more capital, given how many it holds. */
  checkAlliance(held: number): string {
    return held < this.perAlliance ? "" : `Your alliance already holds ${this.perAlliance} capitals.`;
  }

  /** How much more every castle of the holder's alliance produces for one capital. */
  bonus(level: number): number {
    return this.bonusBase + this.bonusPerLevel * (level - 1);
  }

  /**
   * The production bonus for capitals of these levels, at most maxBonus,
   * plus what guild halls of these levels add, at most guildMax.
   */
  totalBonus(levels: number[], guilds: number[] = []): number {
    const guild = guilds.reduce((sum, level) => sum + this.buildingEffect("guildhall", level), 0);
    return Math.min(levels.reduce((sum, level) => sum + this.bonus(level), 0), this.maxBonus) + Math.min(guild, this.guildMax);
  }

  /** The castle boost (CastleState.boost) for capitals of these levels, with guild halls of these levels. */
  boost(levels: number[], resources: string[], guilds: number[] = []): Dict {
    const b = this.totalBonus(levels, guilds);
    const out: Dict = {};
    if (b > 0) for (const r of resources) out[r] = b;
    return out;
  }

  // --- Town buildings ---------------------------------------------------------

  /** The town's buildings at time `t` (building -> level), one finished by then included. */
  buildingLevels(state: VillageState, t: number): Dict {
    const out: Dict = { ...(state.buildings ?? {}) };
    const b = state.building;
    if (b && b.finish <= t) out[b.id] = b.level;
    return out;
  }

  buildingLevel(state: VillageState, id: string, t: number): number {
    return this.buildingLevels(state, t)[id] ?? 0;
  }

  /** The building going up at time `t`, null if none. */
  underWay(state: VillageState, t: number): TownBuild | null {
    const b = state.building;
    return b && b.finish > t ? b : null;
  }

  /** What raising this building to `level` costs. */
  buildingCost(id: string, level: number): Dict {
    const def = this.buildings[id] ?? {};
    const out: Dict = {};
    for (const r of Object.keys(def.cost ?? {})) out[r] = round(Number(def.cost[r]) * Math.pow(Number(def.cost_growth ?? 1), level - 1));
    return out;
  }

  /** How many seconds raising this building to `level` takes. */
  buildingTime(id: string, level: number): number {
    const def = this.buildings[id] ?? {};
    return round(Number(def.time ?? 0) * Math.pow(Number(def.time_growth ?? 1), level - 1));
  }

  /**
   * What this building does at `level`: walls' defence, the market's share
   * more gold, the guardhouse's soldiers or the guild hall's share more production.
   */
  buildingEffect(id: string, level: number): number {
    const def = this.buildings[id] ?? {};
    for (const key of ["defense", "yield_bonus", "guards", "production"]) if (key in def) return Number(def[key]) * level;
    return 0;
  }

  /** Why the holder can't start the next level of this town building now ("" if they can). */
  checkBuild(state: VillageState, id: string, t: number, castle: { canAfford(cost: Dict): boolean }): string {
    const def = this.buildings[id];
    if (typeof id !== "string" || !Object.hasOwn(this.buildings, id)) return "There's no such town building.";
    if (this.underWay(state, t)) return "The town is already building something.";
    const level = this.buildingLevel(state, id, t);
    if (level >= Number(def.max_level ?? 1)) return `${def.name ?? id} is at its highest level.`;
    if (!castle.canAfford(this.buildingCost(id, level + 1))) return "Not enough resources";
    return "";
  }

  /** The state with the next level of this building going up from `t`. */
  startBuild(state: VillageState, id: string, t: number): VillageState {
    const levels = this.buildingLevels(state, t);
    const next = (levels[id] ?? 0) + 1;
    const out: VillageState = { ...state, building: { id, level: next, finish: t + this.buildingTime(id, next) } };
    if (Object.keys(levels).length > 0) out.buildings = levels;
    return out;
  }

  /** The town's gold an hour, with what its market adds. */
  override rate(info: VillageInfo, state: VillageState, t: number): number {
    const base = this.yieldPerHour(info.resource, info.level);
    return round(base * (1 + this.buildingEffect("market", this.buildingLevel(state, "market", t))));
  }

  override wallDefense(info: VillageInfo, state: VillageState, t: number): number {
    return this.palisade(info.level) + this.buildingEffect("walls", this.buildingLevel(state, "walls", t));
  }

  /** The guardhouse's soldiers (in the town guard's mix), fighting for the town's holder. */
  watch(info: VillageInfo, state: VillageState, t: number): Dict {
    const level = this.buildingLevel(state, "guardhouse", t);
    if (level <= 0 || state.owner === "") return {};
    return this.mix(round(this.buildingEffect("guardhouse", level)), info.level);
  }

  /** The town guard, or its holder's guards with the guardhouse's watch beside them. */
  override defenders(info: VillageInfo, state: VillageState, t = 0): Dict {
    const out = super.defenders(info, state, t);
    const extra = this.watch(info, state, t);
    for (const unit of Object.keys(extra)) out[unit] = (out[unit] ?? 0) + extra[unit];
    return out;
  }

  /** As for a village; guardLeft is the holder's own guards still standing, each unit's losses shared with the watch. */
  override attack(units: BuildingRules, barons: BaronRules, info: VillageInfo, state: VillageState, army: Dict, seed: number,
    t: number, waves?: Wave[], tools: Tools = {}, lead: Dict = {}): VillageFight {
    const out = super.attack(units, barons, info, state, army, seed, t, waves, tools, lead);
    const extra = this.watch(info, state, t);
    if (Object.keys(extra).length === 0) return out;
    const left: Dict = {};
    for (const unit of Object.keys(out.guardLeft)) {
      const own = state.guard[unit] ?? 0;
      const n = own > 0 ? Math.floor(out.guardLeft[unit] * own / (own + (extra[unit] ?? 0))) : 0;
      if (n > 0) left[unit] = n;
    }
    return { ...out, guardLeft: left };
  }
}

/** The rules for this village or capital. */
export function rulesFor(rules: { villages: VillageRules; capitals: CapitalRules }, info: VillageInfo): VillageRules {
  return info.capital ? rules.capitals : rules.villages;
}
