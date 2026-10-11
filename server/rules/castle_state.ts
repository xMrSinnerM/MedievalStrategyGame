// One castle's economy: resources, buildings, constructions, garrison,
// training queue and warband. A port of scripts/economy/castle_state.gd.
// The state is the same plain data the game saves (CastleState.to_dict()),
// so it can be stored as JSON and read by either side.
//
// Time is passed in explicitly (Unix seconds).

import { BuildingRules } from "./building_rules.ts";
import { get, type Dict } from "./util.ts";

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
    return out;
  }

  upkeepPerHour(): number {
    let total = 0;
    for (const unit of Object.keys(this.troops)) total += this.troops[unit] * this.rules.unitUpkeep(unit);
    for (const unit of Object.keys(this.field)) total += this.field[unit] * this.rules.unitUpkeep(unit);
    return total;
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

  storageCapacity(): number {
    let total = 0;
    for (const b of this.buildings) total += this.rules.storage(b.type, b.level);
    return total;
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
    if (this.count(type) >= r.maxCount(type, this.keepLevel())) {
      return r.isUnique(type) ? "The castle already has one" : "Upgrade the keep to build more of these";
    }
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
    const unitTime = this.rules.unitTime(unit, this.barracksLevel());
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
      let until = now;
      if (soldierDue) until = this.training[0].next;
      else if (next !== undefined) until = next.finish;
      this.produce(until - this.lastUpdate);
      this.lastUpdate = Math.max(this.lastUpdate, until);
      if (soldierDue) {
        this.finishSoldier();
      } else if (next !== undefined) {
        next.level = next.target;
        next.target = 0;
        next.finish = 0;
      } else {
        break;
      }
    }
  }

  private finishSoldier(): void {
    const batch = this.training[0];
    this.troops[batch.unit] = get(this.troops, batch.unit) + 1;
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
          const eats = group[unit] * this.rules.unitUpkeep(unit);
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
      const upkeep = this.rules.unitUpkeep(worst);
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
    return castle;
  }

  // --- Internals -------------------------------------------------------------

  private checkStartWork(cost: Dict): string {
    if (this.freeBuilders() <= 0) return "All builders are busy";
    if (!this.canAfford(cost)) return "Not enough resources";
    return "";
  }

  private pay(cost: Dict): void {
    for (const r of Object.keys(cost)) this.resources[r] = get(this.resources, r) - cost[r];
  }

  private refund(cost: Dict): void {
    const cap = this.storageCapacity();
    for (const r of Object.keys(cost)) {
      const have = get(this.resources, r);
      this.resources[r] = Math.max(have, Math.min(have + cost[r] * CANCEL_REFUND, cap));
    }
  }

  private addBuilding(type: string, level: number, cell: [number, number]): Building {
    const b: Building = { id: this.nextId, type, level, cell, target: 0, finish: 0 };
    this.nextId += 1;
    this.buildings.push(b);
    return b;
  }
}
