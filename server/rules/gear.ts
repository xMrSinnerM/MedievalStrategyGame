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
  /** Gems in its sockets ("ruby:3"). */
  gems: string[];
}

export interface Commander {
  id: number;
  name: string;
  level: number;
  xp: number;
  /** Slot -> the item worn there. */
  gear: Record<string, Item>;
  /** Skill -> rank learned. */
  skills: Dict;
  /** Unix time the commander's army is home again. */
  away_until: number;
}

export interface Armoury {
  commanders: Commander[];
  /** Slot -> the castellan's item there. */
  castellan: Record<string, Item>;
  bag: Item[];
  next_item: number;
  /** The trade coin, earned by playing. */
  marks: number;
  /** The gem pouch: "ruby:1" -> how many. */
  gems: Dict;
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

/** A skill commanders learn with the points they earn by levelling up. */
export interface Skill {
  id: string;
  name: string;
  branch: string;
  /** Commander level it needs. */
  needs: number;
  /** The skill before it in its branch ("" for none). */
  after: string;
  max: number;
  /** Stat -> percent per rank (the fight stats, and xp). */
  per_rank: Dict;
  text: string;
}

export function newArmoury(): Armoury {
  return { commanders: [], castellan: {}, bag: [], next_item: 1, marks: 0, gems: {} };
}

/** A gem drop or forge seed offset (gear_rules.gd FORGE_SEED). */
export const FORGE_SEED = 50_331_653;

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
  skills: Skill[];
  retrainGold: number;
  gems: Record<string, { name: string; stat: string; color: string }>;
  gemTiers: { name: string; value: number }[];
  fuseCount: number;
  unsocketMarks: number[];
  gemDrop: { base?: number; per_level?: number; max?: number; tiers?: number[][] };
  marksPerLevel: number;
  forgeCount: number;

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
    this.skills = data.skills ?? [];
    this.retrainGold = Number(data.retrain_gold ?? 0);
    this.gems = data.gems ?? {};
    this.gemTiers = data.gem_tiers ?? [];
    this.fuseCount = Number(data.fuse ?? 3);
    this.unsocketMarks = (data.unsocket_marks ?? []).map(Number);
    this.gemDrop = data.gem_drop ?? {};
    this.marksPerLevel = Number(data.marks_per_level ?? 0);
    this.forgeCount = Number(data.forge_count ?? 3);
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
        skills: {}, away_until: 0 });
    }
  }

  /** What gear (and a commander's level) does in a fight: stat -> share, only the stats that are there. */
  effects(gear: Record<string, Item>, level = 1): Dict {
    const sum: Dict = {};
    for (const slot of this.slots) {
      const item = gear[slot];
      if (item === undefined) continue;
      for (const [stat, n] of Object.entries(this.totalStats(item))) sum[stat] = (sum[stat] ?? 0) + n;
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

  /** The castellan's gear plus the castle's defence research. */
  castellanEffects(castle: CastleState): Dict {
    return withResearch(this.effects(castle.armoury.castellan), castle.researchEffects("defence"));
  }

  /** Gear and level, plus skills on top (past the gear caps). */
  commanderEffects(c: Commander): Dict {
    const fx = this.effects(c.gear, c.level);
    for (const [stat, n] of Object.entries(this.skillBonus(c))) {
      if (Object.hasOwn(this.stats, stat)) fx[stat] = (fx[stat] ?? 0) + n / 100;
    }
    return fx;
  }

  commander(castle: CastleState, id: unknown): Commander | undefined {
    return castle.armoury.commanders.find((c) => c.id === id);
  }

  /**
   * The lead for an army: its commander's gear and level plus the castle's
   * attack research, or why not. No commander (`id` undefined, null or 0) is
   * fine: the lead then has id 0 and research alone, or is null if nothing
   * is researched.
   */
  checkLead(castle: CastleState, id: unknown, now: number): Lead | null | string {
    const research = castle.researchEffects("attack");
    if (id === undefined || id === null || id === 0) return Object.keys(research).length > 0 ? { id: 0, name: "", fx: research } : null;
    const c = this.commander(castle, id);
    if (c === undefined) return "No such commander.";
    if (c.away_until > now) return `${c.name} is still away with an army.`;
    return { id: c.id, name: c.name, fx: withResearch(this.commanderEffects(c), research) };
  }

  /** Gives a commander xp; returns the report line for it. */
  addXp(castle: CastleState, id: number, xp: number): LeadReport | undefined {
    const c = this.commander(castle, id);
    if (c === undefined) return undefined;
    const before = c.level;
    xp = Math.round(xp * (1 + (this.skillBonus(c).xp ?? 0) / 100));
    c.xp += xp;
    c.level = this.levelFor(c.xp);
    return { id: c.id, name: c.name, xp, level: c.level, leveled: c.level > before };
  }

  skill(id: unknown): Skill | undefined {
    return this.skills.find((k) => k.id === id);
  }

  /** What a commander's skills add: stat -> percent (fight stats and xp). */
  skillBonus(c: Commander): Dict {
    const out: Dict = {};
    for (const [id, rank] of Object.entries(c.skills)) {
      const k = this.skill(id);
      if (k === undefined) continue;
      for (const [stat, n] of Object.entries(k.per_rank)) out[stat] = (out[stat] ?? 0) + n * rank;
    }
    return out;
  }

  /** Why this commander can't learn a rank of this skill now ("" if they can). */
  checkLearn(castle: CastleState, id: unknown, skillId: unknown): string {
    const c = this.commander(castle, id);
    if (c === undefined) return "No such commander.";
    const k = this.skill(skillId);
    if (k === undefined) return "There's no such skill.";
    if (skillRank(c, k.id) >= k.max) return `${c.name} has mastered ${k.name}.`;
    if (c.level < k.needs) return `${k.name} needs level ${k.needs}.`;
    if (k.after !== "" && skillRank(c, k.after) <= 0) return `Learn ${this.skill(k.after)?.name ?? k.after} first.`;
    if (skillPoints(c) <= 0) return `${c.name} has no skill points left. They earn one each level.`;
    return "";
  }

  learn(castle: CastleState, id: unknown, skillId: unknown): string {
    const why = this.checkLearn(castle, id, skillId);
    if (why === "") {
      const c = this.commander(castle, id)!;
      c.skills[skillId as string] = skillRank(c, skillId as string) + 1;
    }
    return why;
  }

  retrainCost(c: Commander): Dict {
    return { gold: this.retrainGold * c.level };
  }

  checkRetrain(castle: CastleState, id: unknown): string {
    const c = this.commander(castle, id);
    if (c === undefined) return "No such commander.";
    if (Object.keys(c.skills).length === 0) return `${c.name} hasn't learned any skills yet.`;
    if (!castle.canAfford(this.retrainCost(c))) return "Not enough gold.";
    return "";
  }

  /** Forgets every skill, handing the points back, for gold. */
  retrain(castle: CastleState, id: unknown): string {
    const why = this.checkRetrain(castle, id);
    if (why === "") {
      const c = this.commander(castle, id)!;
      castle.pay(this.retrainCost(c));
      c.skills = {};
    }
    return why;
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
    return this.rollItem(rng, rarity, side, slot);
  }

  /** A piece of gear of this rarity, side and slot with random stats and name. */
  private rollItem(rng: Rng, rarity: string, side: GearSide, slot: string): Item {
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
    return { id: 0, slot, side, rarity, name, stats, gems: [] };
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
    this.freeGems(castle, item);
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

  // --- Gems, Marks and the forge ---------------------------------------------------

  /** {kind, tier} of a gem key like "ruby:3", or undefined if there's no such gem. */
  gemParts(key: unknown): { kind: string; tier: number } | undefined {
    if (typeof key !== "string") return undefined;
    const bits = key.split(":");
    if (bits.length !== 2 || !Object.hasOwn(this.gems, bits[0]) || !/^-?\d+$/.test(bits[1])) return undefined;
    const tier = Number(bits[1]);
    if (tier < 1 || tier > this.gemTiers.length || bits[1] !== String(tier)) return undefined;
    return { kind: bits[0], tier };
  }

  gemValue(key: string): number {
    const p = this.gemParts(key);
    return p === undefined ? 0 : Number(this.gemTiers[p.tier - 1].value);
  }

  gemStat(key: string): string {
    const p = this.gemParts(key);
    return p === undefined ? "" : this.gems[p.kind].stat;
  }

  gemSide(key: string): string {
    return String(this.stats[this.gemStat(key)]?.side ?? "");
  }

  gemName(key: string): string {
    const p = this.gemParts(key);
    return p === undefined ? key : `${this.gemTiers[p.tier - 1].name} ${this.gems[p.kind].name}`;
  }

  sockets(item: Item): number {
    return Number(this.rarities[item.rarity]?.sockets ?? 0);
  }

  /** The item's own stats plus its gems': stat -> percent. */
  totalStats(item: Item): Dict {
    const out: Dict = {};
    for (const [stat, n] of Object.entries(item.stats)) out[stat] = (out[stat] ?? 0) + n;
    for (const key of item.gems ?? []) {
      const stat = this.gemStat(key);
      if (stat !== "") out[stat] = (out[stat] ?? 0) + this.gemValue(key);
    }
    return out;
  }

  private freeGems(castle: CastleState, item: Item): void {
    for (const key of item.gems ?? []) if (this.gemParts(key) !== undefined) addGem(castle, key, 1);
    item.gems = [];
  }

  private bagIndex(castle: CastleState, id: unknown): number {
    return castle.armoury.bag.findIndex((x) => x.id === id);
  }

  checkSocket(castle: CastleState, itemId: unknown, key: unknown): string {
    const i = this.bagIndex(castle, itemId);
    if (i < 0) return "There's no such item in your bag.";
    if (this.gemParts(key) === undefined) return "There's no such gem.";
    const k = key as string;
    if (gemCount(castle, k) <= 0) return `You have no ${this.gemName(k)}.`;
    const item = castle.armoury.bag[i];
    if (this.gemSide(k) !== item.side) return `A ${this.gemName(k)} fits ${this.gemSide(k)} gear.`;
    if ((item.gems ?? []).length >= this.sockets(item)) return `Every socket of the ${item.name} is taken.`;
    return "";
  }

  /** Sets a gem from your pouch into a free socket of gear in your bag. */
  socket(castle: CastleState, itemId: unknown, key: unknown): string {
    const why = this.checkSocket(castle, itemId, key);
    if (why === "") {
      (castle.armoury.bag[this.bagIndex(castle, itemId)].gems ??= []).push(key as string);
      addGem(castle, key as string, -1);
    }
    return why;
  }

  unsocketCost(key: string): number {
    const p = this.gemParts(key);
    if (p === undefined || this.unsocketMarks.length === 0) return 0;
    return this.unsocketMarks[Math.min(p.tier, this.unsocketMarks.length) - 1];
  }

  /** Prises gem `index` out of gear in your bag, for Marks; it goes back in your pouch. */
  unsocket(castle: CastleState, itemId: unknown, index: unknown): string {
    const i = this.bagIndex(castle, itemId);
    if (i < 0) return "There's no such item in your bag.";
    const held = (castle.armoury.bag[i].gems ??= []);
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0 || index >= held.length) return "There's no gem there.";
    const key = held[index];
    const cost = this.unsocketCost(key);
    if (castle.armoury.marks < cost) return `Prising out the ${this.gemName(key)} costs ${cost} Marks.`;
    addMarks(castle, -cost);
    held.splice(index, 1);
    if (this.gemParts(key) !== undefined) addGem(castle, key, 1);
    return "";
  }

  checkFuse(castle: CastleState, key: unknown): string {
    const p = this.gemParts(key);
    if (p === undefined) return "There's no such gem.";
    if (p.tier >= this.gemTiers.length) return `A ${this.gemName(key as string)} is as fine as gems get.`;
    if (gemCount(castle, key as string) < this.fuseCount) return `Fusing needs ${this.fuseCount} of the same gem.`;
    return "";
  }

  /** Fuses `fuseCount` gems of one kind and tier into one of the next tier. */
  fuse(castle: CastleState, key: unknown): string {
    const why = this.checkFuse(castle, key);
    if (why === "") {
      const p = this.gemParts(key)!;
      addGem(castle, key as string, -this.fuseCount);
      addGem(castle, gemKey(p.kind, p.tier + 1), 1);
    }
    return why;
  }

  meltMarks(item: Item): number {
    return Number(this.rarities[item.rarity]?.melt ?? 0);
  }

  /** Melts gear from your bag down for Marks; its gems go back in your pouch. */
  melt(castle: CastleState, itemId: unknown): string {
    const i = this.bagIndex(castle, itemId);
    if (i < 0) return "There's no such item in your bag.";
    const [item] = castle.armoury.bag.splice(i, 1);
    this.freeGems(castle, item);
    addMarks(castle, this.meltMarks(item));
    return "";
  }

  nextRarity(rarity: string): string {
    const kinds = Object.keys(this.rarities);
    const i = kinds.indexOf(rarity);
    return i < 0 || i + 1 >= kinds.length ? "" : kinds[i + 1];
  }

  forgeCost(rarity: string): number {
    return Number(this.rarities[rarity]?.forge ?? 0);
  }

  checkForge(castle: CastleState, ids: unknown): string {
    if (!Array.isArray(ids) || ids.length !== this.forgeCount) return `The forge needs ${this.forgeCount} pieces of gear.`;
    const picked: number[] = [];
    for (const id of ids) {
      const i = this.bagIndex(castle, id);
      if (i < 0) return "There's no such item in your bag.";
      if (picked.includes(i)) return `Pick ${this.forgeCount} different pieces.`;
      picked.push(i);
    }
    const first = castle.armoury.bag[picked[0]];
    for (const i of picked) {
      const item = castle.armoury.bag[i];
      if (item.rarity !== first.rarity) return "Forge pieces of the same rarity.";
      if (item.side !== first.side) return "Forge attack gear with attack gear, defence with defence.";
    }
    if (this.nextRarity(first.rarity) === "") return "Legendary gear can't be forged any higher.";
    const cost = this.forgeCost(first.rarity);
    if (castle.armoury.marks < cost) return `Forging ${String(this.rarities[first.rarity].name).toLowerCase()} gear costs ${cost} Marks.`;
    return "";
  }

  /**
   * Forges `forgeCount` bag items of one rarity and side into one random
   * piece of the next rarity, in the slot of the first, for Marks (decided
   * by the first id and the next item id, as in the game).
   */
  forge(castle: CastleState, ids: unknown): string {
    const why = this.checkForge(castle, ids);
    if (why !== "") return why;
    const list = ids as number[];
    const first = castle.armoury.bag[this.bagIndex(castle, list[0])];
    const rarity = this.nextRarity(first.rarity);
    const { side, slot } = first;
    addMarks(castle, -this.forgeCost(first.rarity));
    for (const id of list) {
      const [item] = castle.armoury.bag.splice(this.bagIndex(castle, id), 1);
      this.freeGems(castle, item);
    }
    const rng = new Rng(list[0] * 7919 + castle.armoury.next_item * 104729 + FORGE_SEED);
    this.give(castle, this.rollItem(rng, rarity, side, slot));
    return "";
  }

  gemDropChance(level: number): number {
    return Math.min(Number(this.gemDrop.base ?? 0) + Number(this.gemDrop.per_level ?? 0) * (level - 1), Number(this.gemDrop.max ?? 0));
  }

  /** The gem a beaten camp of `level` drops ("" for none). The same seed gives the same gem. */
  rollGem(level: number, seed: number): string {
    const tiers = this.gemDrop.tiers ?? [];
    const kinds = Object.keys(this.gems);
    if (kinds.length === 0 || tiers.length === 0) return "";
    const rng = new Rng(seed);
    if (rng.randf() >= this.gemDropChance(level)) return "";
    const weights = tiers.map((w) => Math.max(0, Number(w[0]) + Number(w[1]) * (level - 1)));
    const total = weights.reduce((a, b) => a + b, 0);
    let tier = tiers.length;
    let pick = rng.randf() * total;
    for (let t = 0; t < weights.length; t++) {
      if (pick < weights[t]) {
        tier = t + 1;
        break;
      }
      pick -= weights[t];
    }
    return gemKey(kinds[rng.randi() % kinds.length], tier);
  }

  marksForWin(level: number): number {
    return this.marksPerLevel > 0 ? Math.max(1, Math.floor(this.marksPerLevel * level)) : 0;
  }

  /** The gem and Marks a beaten camp of `level` gives, put in the armoury. */
  giveSpoils(castle: CastleState, level: number, seed: number): { gem: string; marks: number } {
    const gem = this.rollGem(level, seed);
    if (gem !== "") addGem(castle, gem, 1);
    const marks = this.marksForWin(level);
    addMarks(castle, marks);
    return { gem, marks };
  }
}

export function gemKey(kind: string, tier: number): string {
  return `${kind}:${tier}`;
}

export function gemCount(castle: CastleState, key: string): number {
  return Object.hasOwn(castle.armoury.gems, key) ? castle.armoury.gems[key] : 0;
}

function addGem(castle: CastleState, key: string, n: number): void {
  const have = gemCount(castle, key) + n;
  if (have > 0) castle.armoury.gems[key] = have;
  else delete castle.armoury.gems[key];
}

export function addMarks(castle: CastleState, n: number): void {
  castle.armoury.marks = Math.max(0, castle.armoury.marks + n);
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
    const gems = Array.isArray(x.gems) ? x.gems.filter((k: unknown) => typeof k === "string") : [];
    return { id: Math.trunc(Number(x.id ?? 0)), slot: String(x.slot ?? ""), side: x.side === "defence" ? "defence" : "attack",
      rarity: String(x.rarity ?? "common"), name: String(x.name ?? ""), stats, gems };
  };
  const gear = (g: Json): Record<string, Item> => {
    const out: Record<string, Item> = {};
    for (const slot of Object.keys(g ?? {})) {
      const it = item(g[slot]);
      if (it !== undefined) out[slot] = it;
    }
    return out;
  };
  const skills = (x: Json): Dict => {
    const out: Dict = {};
    if (x === null || typeof x !== "object" || Array.isArray(x)) return out;
    for (const [id, n] of Object.entries(x)) if (typeof n === "number" && Math.trunc(n) > 0) out[id] = Math.trunc(n);
    return out;
  };
  for (const c of Array.isArray(data.commanders) ? data.commanders : []) {
    a.commanders.push({ id: Math.trunc(Number(c.id ?? 0)), name: String(c.name ?? ""), level: Math.trunc(Number(c.level ?? 1)),
      xp: Math.trunc(Number(c.xp ?? 0)), gear: gear(c.gear), skills: skills(c.skills), away_until: Number(c.away_until ?? 0) });
  }
  a.castellan = gear(data.castellan);
  for (const x of Array.isArray(data.bag) ? data.bag : []) {
    const it = item(x);
    if (it !== undefined) a.bag.push(it);
  }
  a.next_item = Math.trunc(Number(data.next_item ?? 1));
  a.marks = Math.max(0, Math.trunc(Number(data.marks ?? 0)) || 0);
  if (data.gems !== null && typeof data.gems === "object" && !Array.isArray(data.gems)) {
    for (const [k, n] of Object.entries(data.gems)) if (typeof n === "number" && Math.trunc(n) > 0) a.gems[k] = Math.trunc(n);
  }
  return a;
}

export function skillRank(c: Commander, id: string): number {
  return Object.hasOwn(c.skills, id) ? c.skills[id] : 0;
}

/** Skill points not yet spent: one for each level past the first. */
export function skillPoints(c: Commander): number {
  return c.level - 1 - Object.values(c.skills).reduce((a, b) => a + b, 0);
}

/** Gear effects with research's added on top. */
export function withResearch(fx: Dict, research: Dict): Dict {
  for (const stat of Object.keys(research)) fx[stat] = (fx[stat] ?? 0) + research[stat];
  return fx;
}
