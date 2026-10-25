// One castle's economy: resources, buildings, constructions, garrison,
// training queue, warband and academy research. A port of scripts/economy/castle_state.gd.
// The state is the same plain data the game saves (CastleState.to_dict()),
// so it can be stored as JSON and read by either side.
//
// Time is passed in explicitly (Unix seconds).

import { checkLayout, checkTools, DEFAULT_LAYOUT, WALLS, type Layout, type Tools } from "./battle.ts";
import { BuildingRules } from "./building_rules.ts";
import { newArmoury, readArmoury, type Armoury } from "./gear.ts";
import { get, round, type Dict } from "./util.ts";

/** Share of the cost given back when a construction is cancelled. */
export const CANCEL_REFUND = 0.75;

export interface Building {
  id: number;
  type: string;
  level: number;
  cell: [number, number];
  target: number;
  finish: number;
}

export interface Batch {
  unit: string;
  remaining: number;
  unit_time: number;
  next: number;
}

/** Siege tools being built in the workshop, one after another. */
export interface Craft {
  tool: string;
  remaining: number;
  unit_time: number;
  next: number;
}

/** The study under way in the academy. */
export interface Study {
  study: string;
  target: number;
  finish: number;
}

/** Lifetime counts the quests check (server/rules/quests.ts). */
export interface Stats {
  /** Soldiers trained. */
  trained: number;
  /** Resources paid for buildings and soldiers, less what cancelling gave back. */
  spent: number;
  /** Robber baron camps beaten. */
  barons: number;
  /** Resources armies brought home. */
  looted: number;
}

/** Where the castle stands with its quests (server/rules/quests.ts). */
export interface QuestLog {
  /** Index of the story quest being worked on (all done at the end of the chain). */
  story: number;
  /** The day (Unix days) the daily tasks were picked for, -1 before the first. */
  day: number;
  /** Keep level when the day began, which sets the tasks' targets and rewards. */
  keep: number;
  /** The kinds of daily task picked for today. */
  picks: string[];
  /** The counts when the day began; tasks count from here. */
  base: Dict;
  /** Daily tasks (indexes into picks) already claimed today. */
  claimed: number[];
  /** Today's coffer has been opened. */
  chest: boolean;
  /** Days in a row the coffer was opened, and the last such day. */
  streak: number;
  chest_day: number;
}

export function newStats(): Stats {
  return { trained: 0, spent: 0, barons: 0, looted: 0 };
}

export function newQuestLog(): QuestLog {
  return { story: 0, day: -1, keep: 1, picks: [], base: {}, claimed: [], chest: false, streak: 0, chest_day: -1 };
}

export interface CastleData {
  id: string;
  name: string;
  owner: string;
  resources: Dict;
  buildings: Building[];
  last_update: number;
  next_id: number;
  troops: Dict;
  training: Batch[];
  hunger: number;
  field: Dict;
  field_ready: boolean;
  layout: Layout;
  stats: Stats;
  quests: QuestLog;
  tools: Dict;
  crafting: Craft[];
  defence_tools: Tools;
  armoury: Armoury;
  boost: Dict;
  limits: Limits | null;
  research: Dict;
  studying: Study | null;
}

/** What an outpost may build (outposts.ts): only these types, its keep up to `keep`. */
export interface Limits {
  types: string[];
  keep: number;
}

export class CastleState {
  id = "";
  castleName = "";
  owner = "player";
  rules: BuildingRules;
  resources: Dict = {};
  buildings: Building[] = [];
  lastUpdate = 0;
  troops: Dict = {};
  training: Batch[] = [];
  hunger = 0;
  field: Dict = {};
  fieldReady = false;
  /** Where the garrison stands when the castle is stormed (siege() in battle.ts). */
  layout: Layout = { ...DEFAULT_LAYOUT };
  stats: Stats = newStats();
  quests: QuestLog = newQuestLog();
  /** Siege tools in store, the workshop's queue, and the defence tools posted on each wall. */
  tools: Dict = {};
  crafting: Craft[] = [];
  defenceTools: Tools = {};
  /** Commanders, the castellan's gear and the bag of gear (gear.ts). */
  armoury: Armoury = newArmoury();
  /** Extra production by resource (0.5 for half as much again): an outpost's region. */
  boost: Dict = {};
  /** An outpost's building limits; null for a normal castle. */
  limits: Limits | null = null;
  /** Studies researched in the academy (study -> level) and the one under way. */
  research: Dict = {};
  studying: Study | null = null;
  private nextId = 1;

  constructor(rules: BuildingRules) {
    this.rules = rules;
  }

  static createNew(rules: BuildingRules, id: string, name: string, owner: string, now: number): CastleState {
    const castle = new CastleState(rules);
    castle.id = id;
    castle.castleName = name;
    castle.owner = owner;
    castle.lastUpdate = now;
    for (const r of rules.resources) castle.resources[r] = Number(rules.start.resources?.[r] ?? 0);
    for (const b of rules.start.buildings ?? []) {
      const cell: [number, number] = b.cell ? [Number(b.cell[0]), Number(b.cell[1])] : [-1, -1];
      castle.addBuilding(b.type, Number(b.level), cell);
    }
    return castle;
  }

  // --- Queries ---------------------------------------------------------------

  keepLevel(): number {
    for (const b of this.buildings) if (b.type === "keep") return b.level;
    return 0;
  }

  getBuilding(id: number): Building | undefined {
    return this.buildings.find((b) => b.id === id);
  }

  count(type: string): number {
    return this.buildings.filter((b) => b.type === type).length;
  }

  constructions(): Building[] {
    return this.buildings.filter((b) => b.target > 0);
  }

  freeBuilders(): number {
    return this.rules.builders(this.keepLevel()) - this.constructions().length;
  }

  productionPerHour(): Dict {
    const out: Dict = {};
    for (const r of this.rules.resources) out[r] = 0;
    for (const b of this.buildings) {
      const p = this.rules.production(b.type, b.level);
      for (const r of Object.keys(p)) out[r] = get(out, r) + p[r];
    }
    for (const r of Object.keys(this.boost)) if (r in out) out[r] *= 1 + this.boost[r];
    for (const r of Object.keys(out)) {
      const more = this.researchBonus(r);
      if (more !== 0) out[r] *= 1 + more;
    }
    return out;
  }

  upkeepPerHour(): number {
    let total = 0;
    for (const unit of Object.keys(this.troops)) total += this.troops[unit] * this.unitUpkeep(unit);
    for (const unit of Object.keys(this.field)) total += this.field[unit] * this.unitUpkeep(unit);
    return total;
  }

  /** Food one soldier eats per hour here, after Field Rations. */
  unitUpkeep(unit: string): number {
    return this.rules.unitUpkeep(unit) * (1 + this.researchBonus("upkeep"));
  }

  netPerHour(): Dict {
    const out = this.productionPerHour();
    out.food = get(out, "food") - this.upkeepPerHour();
    return out;
  }

  troopCount(): number {
    return Object.values(this.troops).reduce((n, v) => n + v, 0);
  }

  barracksLevel(): number {
    for (const b of this.buildings) if (b.type === "barracks") return b.level;
    return 0;
  }

  checkRecruit(unit: string, amount: number): string {
    const r = this.rules;
    if (!r.hasUnit(unit)) return "Unknown unit";
    if (this.barracksLevel() <= 0) return "Build a barracks first";
    if (this.barracksLevel() < r.unitBarracksLevel(unit)) return `Needs barracks level ${r.unitBarracksLevel(unit)}`;
    if (!Number.isInteger(amount) || amount < 1 || amount > r.maxBatch) return `Train between 1 and ${r.maxBatch} at a time`;
    if (this.training.length >= r.queueSize) return "The training queue is full";
    if (!this.canAfford(r.unitCost(unit, amount))) return "Not enough resources";
    return "";
  }

  workshopLevel(): number {
    for (const b of this.buildings) if (b.type === "workshop") return b.level;
    return 0;
  }

  wallLevel(): number {
    for (const b of this.buildings) if (b.type === "wall") return b.level;
    return 0;
  }

  checkCraft(tool: string, amount: number): string {
    const r = this.rules;
    if (!r.hasTool(tool)) return "Unknown siege tool";
    if (this.workshopLevel() <= 0) return "Build a siege workshop first";
    if (this.workshopLevel() < r.toolWorkshopLevel(tool)) return `Needs workshop level ${r.toolWorkshopLevel(tool)}`;
    if (!Number.isInteger(amount) || amount < 1 || amount > r.maxBatch) return `Build between 1 and ${r.maxBatch} at a time`;
    if (this.crafting.length >= r.queueSize) return "The workshop queue is full";
    if (!this.canAfford(r.toolCost(tool, amount))) return "Not enough resources";
    return "";
  }

  /** Why these defence tools can't stand on the walls ("" if they can). */
  checkDefenceTools(tools: unknown): string {
    const checked = checkTools(this.rules, tools, "defence", this.defenceSlots(), this.tools);
    return typeof checked === "string" ? checked : "";
  }

  /** Defence tools that fit on each wall: by wall level, plus Murder Holes. */
  defenceSlots(): number {
    const n = this.rules.toolSlots(this.wallLevel());
    return n > 0 ? n + Math.trunc(this.researchBonus("defence_slots")) : 0;
  }

  storageCapacity(): number {
    let total = 0;
    for (const b of this.buildings) total += this.rules.storage(b.type, b.level);
    return total * (1 + this.researchBonus("storage"));
  }

  defense(): number {
    let total = 0;
    for (const b of this.buildings) total += this.rules.defense(b.type, b.level);
    return total;
  }

  canAfford(cost: Dict): boolean {
    for (const r of Object.keys(cost)) if (get(this.resources, r) + 0.0001 < cost[r]) return false;
    return true;
  }

  checkBuild(type: string): string {
    const r = this.rules;
    if (!r.hasType(type)) return "Unknown building";
    if (r.isPerimeter(type)) return "This is built around the castle, not placed";
    if (this.limits && !this.limits.types.includes(type)) return "An outpost can't have one of these";
    if (this.count(type) >= r.maxCount(type, this.keepLevel())) {
      return r.isUnique(type) ? "The castle already has one" : "Upgrade the keep to build more of these";
    }
    if (this.keepLevel() < r.requiredKeep(type)) return `Needs keep level ${r.requiredKeep(type)}`;
    return this.checkStartWork(r.cost(type, 1));
  }

  checkPlace(type: string, cell: [number, number]): string {
    const reason = this.checkBuild(type);
    if (reason !== "") return reason;
    if (!this.fits(type, cell)) return "There's no room there";
    return "";
  }

  checkUpgrade(id: number): string {
    const b = this.getBuilding(id);
    if (b === undefined) return "No such building";
    if (b.target > 0) return "Already under construction";
    if (this.limits && b.type === "keep" && b.level >= this.limits.keep) return "An outpost's keep can't go higher";
    if (b.level >= this.rules.maxLevel(b.type, this.keepLevel())) {
      if (b.type !== "keep" && b.level < Number(this.rules.types[b.type].max_level ?? 10)) return "Upgrade the keep first";
      return "Fully upgraded";
    }
    return this.checkStartWork(this.rules.cost(b.type, b.level + 1));
  }

  fits(type: string, cell: [number, number], ignoreId = -1): boolean {
    const [w, h] = this.rules.size(type);
    const [x, y] = cell;
    const g = this.rules.gridSize;
    if (!Number.isInteger(x) || !Number.isInteger(y)) return false;
    if (x < 0 || y < 0 || x + w > g || y + h > g) return false;
    for (const b of this.buildings) {
      if (b.id === ignoreId || b.cell[0] < 0) continue;
      const [bw, bh] = this.rules.size(b.type);
      if (x < b.cell[0] + bw && b.cell[0] < x + w && y < b.cell[1] + bh && b.cell[1] < y + h) return false;
    }
    return true;
  }

  /** Seconds to train one soldier here: by barracks level, then Drill Yards. */
  unitTime(unit: string): number {
    return shorter(this.rules.unitTime(unit, this.barracksLevel()), this.researchBonus("recruit_time"));
  }

  /** Seconds to build one siege tool here: by workshop level, then Siegecraft. */
  toolTime(tool: string): number {
    return shorter(this.rules.toolTime(tool, this.workshopLevel()), this.researchBonus("craft_time"));
  }

  // --- Research --------------------------------------------------------------

  academyLevel(): number {
    for (const b of this.buildings) if (b.type === "academy") return b.level;
    return 0;
  }

  studyLevel(study: string): number {
    return this.research[study] ?? 0;
  }

  /** What every study researched adds up to for one effect: 0.12 for 12% more, -0.1 for 10% less. */
  researchBonus(effect: string): number {
    let total = 0;
    for (const study of Object.keys(this.research)) {
      const per = this.rules.studyEffects(study)[effect];
      if (per !== undefined) total += Number(per) * this.research[study];
    }
    return total;
  }

  /** The battle effects research gives (stat -> share): "attack" for your armies, "defence" for your castle. */
  researchEffects(side: "attack" | "defence"): Dict {
    const out: Dict = {};
    for (const stat of side === "attack" ? ["wall_attack", "yard_attack"] : ["wall_defence", "yard_defence", "wall_bonus"]) {
      const n = this.researchBonus(stat);
      if (n > 0) out[stat] = n;
    }
    return out;
  }

  /** Multiplier on how long your armies march (Forced March). */
  marchFactor(): number {
    return Math.max(1 + this.researchBonus("march_time"), 0.1);
  }

  /** How much of each resource Hidden Cellars keep safe from plunder. */
  hidden(): number {
    return this.storageCapacity() * this.researchBonus("hidden");
  }

  /**
   * After a battle at the castle: the Infirmary sends back a share of the
   * garrison that fell (`before` is the garrison before it). Returns unit -> healed.
   */
  heal(before: Dict): Dict {
    const share = this.researchBonus("heal");
    const out: Dict = {};
    if (share <= 0) return out;
    for (const unit of Object.keys(before)) {
      const n = Math.floor((before[unit] - (this.troops[unit] ?? 0)) * share);
      if (n > 0) {
        this.troops[unit] = (this.troops[unit] ?? 0) + n;
        out[unit] = n;
      }
    }
    return out;
  }

  /** Why the academy can't start on this study's next level, or "" if it can. */
  checkResearch(study: string): string {
    const r = this.rules;
    if (!r.hasStudy(study)) return "Unknown study";
    if (this.academyLevel() <= 0) return "Build an academy first";
    const level = this.studyLevel(study);
    if (level >= r.studyMaxLevel(study)) return "Fully researched";
    if (this.academyLevel() < r.studyAcademyLevel(study)) return `Needs academy level ${r.studyAcademyLevel(study)}`;
    const needs = r.studyRequires(study);
    for (const other of Object.keys(needs)) {
      if (this.studyLevel(other) < Number(needs[other])) return `Needs ${r.studyName(other)} level ${Number(needs[other])}`;
    }
    if (this.studying !== null) return "The academy is already researching";
    if (!this.canAfford(r.studyCost(study, level + 1))) return "Not enough resources";
    return "";
  }

  /** Seconds the next level of this study takes in this academy. */
  researchTime(study: string): number {
    return this.rules.studyTime(study, this.studyLevel(study) + 1, this.academyLevel());
  }

  startResearch(study: string, now: number): boolean {
    this.advanceTo(now);
    if (this.checkResearch(study) !== "") return false;
    const target = this.studyLevel(study) + 1;
    this.pay(this.rules.studyCost(study, target));
    this.studying = { study, target, finish: now + this.researchTime(study) };
    return true;
  }

  cancelResearch(now: number): boolean {
    this.advanceTo(now);
    if (this.studying === null) return false;
    this.refund(this.rules.studyCost(this.studying.study, this.studying.target));
    this.studying = null;
    return true;
  }

  // --- Orders ----------------------------------------------------------------

  place(type: string, cell: [number, number], now: number): number {
    this.advanceTo(now);
    if (this.checkPlace(type, cell) !== "") return -1;
    this.pay(this.rules.cost(type, 1));
    const b = this.addBuilding(type, 0, cell);
    b.target = 1;
    b.finish = now + this.rules.buildTime(type, 1);
    return b.id;
  }

  upgrade(id: number, now: number): boolean {
    this.advanceTo(now);
    if (this.checkUpgrade(id) !== "") return false;
    const b = this.getBuilding(id)!;
    this.pay(this.rules.cost(b.type, b.level + 1));
    b.target = b.level + 1;
    b.finish = now + this.rules.buildTime(b.type, b.target);
    return true;
  }

  cancel(id: number, now: number): boolean {
    this.advanceTo(now);
    const b = this.getBuilding(id);
    if (b === undefined || b.target <= 0) return false;
    this.refund(this.rules.cost(b.type, b.target));
    b.target = 0;
    b.finish = 0;
    if (b.level === 0) this.buildings.splice(this.buildings.indexOf(b), 1);
    return true;
  }

  recruit(unit: string, amount: number, now: number): boolean {
    this.advanceTo(now);
    if (this.checkRecruit(unit, amount) !== "") return false;
    this.pay(this.rules.unitCost(unit, amount));
    const unitTime = this.unitTime(unit);
    this.training.push({ unit, remaining: amount, unit_time: unitTime, next: this.training.length === 0 ? now + unitTime : 0 });
    return true;
  }

  cancelTraining(index: number, now: number): boolean {
    this.advanceTo(now);
    if (!Number.isInteger(index) || index < 0 || index >= this.training.length) return false;
    const batch = this.training[index];
    this.refund(this.rules.unitCost(batch.unit, batch.remaining));
    this.training.splice(index, 1);
    if (index === 0 && this.training.length > 0) this.training[0].next = now + this.training[0].unit_time;
    return true;
  }

  craft(tool: string, amount: number, now: number): boolean {
    this.advanceTo(now);
    if (this.checkCraft(tool, amount) !== "") return false;
    this.pay(this.rules.toolCost(tool, amount));
    const unitTime = this.toolTime(tool);
    this.crafting.push({ tool, remaining: amount, unit_time: unitTime, next: this.crafting.length === 0 ? now + unitTime : 0 });
    return true;
  }

  cancelCrafting(index: number, now: number): boolean {
    this.advanceTo(now);
    if (!Number.isInteger(index) || index < 0 || index >= this.crafting.length) return false;
    const batch = this.crafting[index];
    this.refund(this.rules.toolCost(batch.tool, batch.remaining));
    this.crafting.splice(index, 1);
    if (index === 0 && this.crafting.length > 0) this.crafting[0].next = now + this.crafting[0].unit_time;
    return true;
  }

  setDefenceTools(tools: unknown): string {
    const checked = checkTools(this.rules, tools, "defence", this.defenceSlots(), this.tools);
    if (typeof checked === "string") return checked;
    this.defenceTools = checked;
    return "";
  }

  /** Takes tools out of the store (attack tools sent with an army, or tools lost). */
  useTools(tools: Tools): void {
    for (const w of WALLS) {
      for (const [tool, n] of Object.entries(tools[w] ?? {})) {
        this.tools[tool] = Math.max(0, (this.tools[tool] ?? 0) - n);
        if (this.tools[tool] === 0) delete this.tools[tool];
      }
    }
  }

  /** Defence tools lost when their walls fell: off the walls and out of the store. */
  loseDefenceTools(lost: Tools): void {
    for (const w of WALLS) {
      const posted = this.defenceTools[w];
      if (posted === undefined) continue;
      for (const [tool, n] of Object.entries(lost[w] ?? {})) {
        posted[tool] = Math.max(0, (posted[tool] ?? 0) - n);
        if (posted[tool] === 0) delete posted[tool];
      }
      if (Object.keys(posted).length === 0) delete this.defenceTools[w];
    }
    this.useTools(lost);
  }

  move(id: number, cell: [number, number]): boolean {
    const b = this.getBuilding(id);
    if (b === undefined || b.cell[0] < 0 || !this.fits(b.type, cell, id)) return false;
    b.cell = [cell[0], cell[1]];
    return true;
  }

  // --- Time ------------------------------------------------------------------

  advanceTo(now: number): void {
    while (true) {
      let next: Building | undefined;
      for (const b of this.buildings) {
        if (b.target > 0 && b.finish <= now && (next === undefined || b.finish < next.finish)) next = b;
      }
      const soldierDue = this.training.length > 0 && this.training[0].next <= now &&
        (next === undefined || this.training[0].next < next.finish);
      // A study finishes first if it is done before the soldier or building.
      const study = this.studying;
      const studyDue = study !== null && study.finish <= now &&
        (soldierDue ? study.finish < this.training[0].next : (next === undefined || study.finish < next.finish));
      let until = now;
      if (studyDue) until = study!.finish;
      else if (soldierDue) until = this.training[0].next;
      else if (next !== undefined) until = next.finish;
      this.produce(until - this.lastUpdate);
      this.lastUpdate = Math.max(this.lastUpdate, until);
      if (studyDue) {
        this.research[study!.study] = study!.target;
        this.studying = null;
      } else if (soldierDue) {
        this.finishSoldier();
      } else if (next !== undefined) {
        next.level = next.target;
        next.target = 0;
        next.finish = 0;
      } else {
        break;
      }
    }
    this.finishCrafts(now);
  }

  /** Tools don't eat or produce, so the workshop just catches up. */
  private finishCrafts(now: number): void {
    while (this.crafting.length > 0 && this.crafting[0].next <= now) {
      const batch = this.crafting[0];
      this.tools[batch.tool] = get(this.tools, batch.tool) + 1;
      batch.remaining -= 1;
      const doneAt = batch.next;
      if (batch.remaining > 0) {
        batch.next = doneAt + batch.unit_time;
        continue;
      }
      this.crafting.shift();
      if (this.crafting.length > 0) this.crafting[0].next = doneAt + this.crafting[0].unit_time;
    }
  }

  private finishSoldier(): void {
    const batch = this.training[0];
    this.troops[batch.unit] = get(this.troops, batch.unit) + 1;
    this.stats.trained += 1;
    batch.remaining -= 1;
    const doneAt = batch.next;
    if (batch.remaining > 0) {
      batch.next = doneAt + batch.unit_time;
      return;
    }
    this.training.shift();
    if (this.training.length > 0) this.training[0].next = doneAt + this.training[0].unit_time;
  }

  private produce(seconds: number): void {
    if (seconds <= 0) return;
    const rates = this.netPerHour();
    const cap = this.storageCapacity();
    for (const r of Object.keys(rates)) {
      const have = get(this.resources, r);
      const after = have + rates[r] * seconds / 3600;
      if (rates[r] >= 0) {
        this.resources[r] = Math.max(have, Math.min(after, cap));
      } else if (after >= 0) {
        this.resources[r] = after;
      } else {
        this.resources[r] = 0;
        this.hunger += -after;
      }
    }
    if (get(this.resources, "food") > 0) this.hunger = 0;
    this.desert();
  }

  private desert(): void {
    while (this.hunger > 0) {
      let worst = "";
      let pool: Dict = {};
      let most = 0;
      for (const group of [this.troops, this.field]) {
        for (const unit of Object.keys(group)) {
          const eats = group[unit] * this.unitUpkeep(unit);
          if (group[unit] > 0 && eats > most) {
            most = eats;
            worst = unit;
            pool = group;
          }
        }
      }
      if (worst === "") {
        this.hunger = 0;
        return;
      }
      const upkeep = this.unitUpkeep(worst);
      const leaving = Math.min(Math.trunc(this.hunger / upkeep), pool[worst]);
      if (leaving <= 0) return;
      pool[worst] -= leaving;
      this.hunger -= leaving * upkeep;
    }
  }

  // --- Saving ----------------------------------------------------------------

  toDict(): CastleData {
    return {
      id: this.id,
      name: this.castleName,
      owner: this.owner,
      resources: { ...this.resources },
      buildings: this.buildings.map((b) => ({ ...b, cell: [b.cell[0], b.cell[1]] as [number, number] })),
      last_update: this.lastUpdate,
      next_id: this.nextId,
      troops: { ...this.troops },
      training: this.training.map((t) => ({ ...t })),
      hunger: this.hunger,
      field: { ...this.field },
      field_ready: this.fieldReady,
      layout: { ...this.layout },
      stats: { ...this.stats },
      quests: structuredClone(this.quests),
      tools: { ...this.tools },
      crafting: this.crafting.map((c) => ({ ...c })),
      defence_tools: structuredClone(this.defenceTools),
      armoury: structuredClone(this.armoury),
      boost: { ...this.boost },
      limits: this.limits ? { types: [...this.limits.types], keep: this.limits.keep } : null,
      research: { ...this.research },
      studying: this.studying ? { ...this.studying } : null,
    };
  }

  // deno-lint-ignore no-explicit-any
  static fromDict(rules: BuildingRules, data: any): CastleState {
    const castle = new CastleState(rules);
    castle.id = data.id ?? "";
    castle.castleName = data.name ?? "";
    castle.owner = data.owner ?? "player";
    castle.lastUpdate = Number(data.last_update ?? 0);
    castle.nextId = Number(data.next_id ?? 1);
    for (const r of rules.resources) castle.resources[r] = Number(data.resources?.[r] ?? 0);
    for (const b of data.buildings ?? []) {
      if (!rules.hasType(b.type ?? "")) continue;
      castle.buildings.push({
        id: Number(b.id), type: String(b.type), level: Number(b.level),
        cell: [Number(b.cell[0]), Number(b.cell[1])],
        target: Number(b.target ?? 0), finish: Number(b.finish ?? 0),
      });
    }
    for (const unit of Object.keys(data.troops ?? {})) {
      if (rules.hasUnit(unit)) castle.troops[unit] = Math.trunc(Number(data.troops[unit]));
    }
    for (const t of data.training ?? []) {
      if (rules.hasUnit(t.unit ?? "")) {
        castle.training.push({ unit: String(t.unit), remaining: Number(t.remaining), unit_time: Number(t.unit_time), next: Number(t.next ?? 0) });
      }
    }
    if (castle.training.length > 0 && castle.training[0].next <= 0) {
      castle.training[0].next = castle.lastUpdate + castle.training[0].unit_time;
    }
    castle.hunger = Number(data.hunger ?? 0);
    for (const unit of Object.keys(data.field ?? {})) {
      if (rules.hasUnit(unit)) castle.field[unit] = Math.trunc(Number(data.field[unit]));
    }
    castle.fieldReady = Boolean(data.field_ready ?? false);
    if (checkLayout(data.layout) === "") {
      for (const key of Object.keys(DEFAULT_LAYOUT) as (keyof Layout)[]) castle.layout[key] = data.layout[key];
    }
    // Castles saved before quests have no stats or quest log yet.
    const stats = data.stats ?? {};
    castle.stats = { trained: Math.trunc(Number(stats.trained ?? 0)), spent: Number(stats.spent ?? 0),
      barons: Math.trunc(Number(stats.barons ?? 0)), looted: Number(stats.looted ?? 0) };
    const q = data.quests ?? {};
    const base: Dict = {};
    for (const k of Object.keys(q.base ?? {})) base[k] = Number(q.base[k]);
    castle.quests = {
      story: Math.trunc(Number(q.story ?? 0)), day: Math.trunc(Number(q.day ?? -1)), keep: Math.trunc(Number(q.keep ?? 1)),
      picks: (q.picks ?? []).map(String), base, claimed: (q.claimed ?? []).map((i: unknown) => Math.trunc(Number(i))),
      chest: Boolean(q.chest ?? false), streak: Math.trunc(Number(q.streak ?? 0)), chest_day: Math.trunc(Number(q.chest_day ?? -1)),
    };
    for (const tool of Object.keys(data.tools ?? {})) {
      const n = Math.trunc(Number(data.tools[tool]));
      if (rules.hasTool(tool) && n > 0) castle.tools[tool] = n;
    }
    for (const c of data.crafting ?? []) {
      if (rules.hasTool(c.tool ?? "")) {
        castle.crafting.push({ tool: String(c.tool), remaining: Number(c.remaining), unit_time: Number(c.unit_time), next: Number(c.next ?? 0) });
      }
    }
    if (castle.crafting.length > 0 && castle.crafting[0].next <= 0) {
      castle.crafting[0].next = castle.lastUpdate + castle.crafting[0].unit_time;
    }
    for (const w of WALLS) {
      const set: Dict = {};
      for (const tool of Object.keys(data.defence_tools?.[w] ?? {})) {
        const n = Math.trunc(Number(data.defence_tools[w][tool]));
        if (rules.hasTool(tool) && n > 0) set[tool] = n;
      }
      if (Object.keys(set).length > 0) castle.defenceTools[w] = set;
    }
    castle.armoury = readArmoury(data.armoury);
    for (const r of Object.keys(data.boost ?? {})) {
      if (rules.resources.includes(r)) castle.boost[r] = Number(data.boost[r]);
    }
    if (data.limits) castle.limits = { types: (data.limits.types ?? []).map(String), keep: Number(data.limits.keep ?? 1) };
    // Castles saved before the academy have researched nothing.
    for (const study of Object.keys(data.research ?? {})) {
      const n = Math.trunc(Number(data.research[study]));
      if (rules.hasStudy(study) && n > 0) castle.research[study] = Math.min(n, rules.studyMaxLevel(study));
    }
    const st = data.studying;
    if (st && typeof st === "object" && rules.hasStudy(String(st.study ?? ""))) {
      castle.studying = { study: String(st.study), target: Math.trunc(Number(st.target ?? 1)), finish: Number(st.finish ?? 0) };
    }
    return castle;
  }

  // --- Internals -------------------------------------------------------------

  private checkStartWork(cost: Dict): string {
    if (this.freeBuilders() <= 0) return "All builders are busy";
    if (!this.canAfford(cost)) return "Not enough resources";
    return "";
  }

  /** Takes what this costs (also what something outside the castle costs, such as a capital's town building). */
  pay(cost: Dict): void {
    for (const r of Object.keys(cost)) {
      this.resources[r] = get(this.resources, r) - cost[r];
      this.stats.spent += cost[r];
    }
  }

  private refund(cost: Dict): void {
    const cap = this.storageCapacity();
    for (const r of Object.keys(cost)) {
      const have = get(this.resources, r);
      this.resources[r] = Math.max(have, Math.min(have + cost[r] * CANCEL_REFUND, cap));
      this.stats.spent -= cost[r] * CANCEL_REFUND;
    }
  }

  private addBuilding(type: string, level: number, cell: [number, number]): Building {
    const b: Building = { id: this.nextId, type, level, cell, target: 0, finish: 0 };
    this.nextId += 1;
    this.buildings.push(b);
    return b;
  }
}

/** A time after research (change -0.1 for 10% faster), whole seconds, at least one. */
function shorter(time: number, change: number): number {
  return change === 0 ? time : Math.max(round(time * (1 + change)), 1);
}
