// The castle economy's numbers, read from data/buildings.json and
// data/units.json. A port of scripts/economy/building_rules.gd: values for
// level N grow from the level-1 value as base * growth^(N - 1).

import { clamp, round, type Dict } from "./util.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

export class BuildingRules {
  resources: string[] = [];
  gridSize = 24;
  start: Json = {};
  types: Record<string, Json> = {};
  units: Record<string, Json> = {};
  queueSize = 5;
  maxBatch = 50;
  timePerBarracksLevel = 0.92;

  constructor(buildings: Json, units: Json) {
    this.resources = (buildings.resources ?? []).map(String);
    this.gridSize = Number(buildings.grid_size ?? 24);
    this.start = buildings.start ?? {};
    this.types = buildings.buildings ?? {};
    this.units = units.units ?? {};
    this.queueSize = Number(units.queue_size ?? 5);
    this.maxBatch = Number(units.max_batch ?? 50);
    this.timePerBarracksLevel = Number(units.time_per_barracks_level ?? 0.92);
  }

  hasType(type: string): boolean {
    return Object.hasOwn(this.types, type);
  }

  size(type: string): [number, number] {
    const s = this.types[type].size ?? [0, 0];
    return [Number(s[0]), Number(s[1])];
  }

  isPerimeter(type: string): boolean {
    return this.types[type].placement === "perimeter";
  }

  isUnique(type: string): boolean {
    return this.types[type].unique === true;
  }

  cost(type: string, level: number): Dict {
    const def = this.types[type];
    const factor = Math.pow(Number(def.cost_growth ?? 1.5), level - 1);
    const out: Dict = {};
    for (const r of Object.keys(def.cost ?? {})) out[r] = round(Number(def.cost[r]) * factor);
    return out;
  }

  buildTime(type: string, level: number): number {
    const def = this.types[type];
    return round(Number(def.time ?? 30) * Math.pow(Number(def.time_growth ?? 1.6), level - 1));
  }

  production(type: string, level: number): Dict {
    const def = this.types[type];
    const out: Dict = {};
    if (level <= 0) return out;
    const factor = Math.pow(Number(def.production_growth ?? 1.35), level - 1);
    for (const r of Object.keys(def.produces ?? {})) out[r] = Number(def.produces[r]) * factor;
    return out;
  }

  storage(type: string, level: number): number {
    const def = this.types[type];
    if (level <= 0 || !("storage" in def)) return 0;
    return Number(def.storage) * Math.pow(Number(def.storage_growth ?? 1.5), level - 1);
  }

  defense(type: string, level: number): number {
    const def = this.types[type];
    if (level <= 0 || !("defense" in def)) return 0;
    return Number(def.defense) * Math.pow(Number(def.defense_growth ?? 1.5), level - 1);
  }

  builders(keepLevel: number): number {
    const table: number[] = this.types.keep?.builders ?? [1];
    return Number(table[clamp(keepLevel - 1, 0, table.length - 1)]);
  }

  maxLevel(type: string, keepLevel: number): number {
    const cap = Number(this.types[type].max_level ?? 10);
    return type === "keep" ? cap : Math.min(cap, keepLevel * 2);
  }

  maxCount(type: string, keepLevel: number): number {
    if (this.isUnique(type)) return 1;
    const table: number[] = this.types[type].max_count ?? [1];
    return Number(table[clamp(keepLevel - 1, 0, table.length - 1)]);
  }

  // --- Troops ---------------------------------------------------------------

  hasUnit(unit: string): boolean {
    return Object.hasOwn(this.units, unit);
  }

  unitCost(unit: string, count = 1): Dict {
    const out: Dict = {};
    const cost = this.units[unit].cost ?? {};
    for (const r of Object.keys(cost)) out[r] = Number(cost[r]) * count;
    return out;
  }

  unitTime(unit: string, barracksLevel: number): number {
    return round(Number(this.units[unit].time ?? 30) *
      Math.pow(this.timePerBarracksLevel, Math.max(barracksLevel - 1, 0)));
  }

  unitUpkeep(unit: string): number {
    return Number(this.units[unit].upkeep ?? 1.0);
  }

  unitStat(unit: string, stat: string): number {
    return Number(this.units[unit][stat] ?? 0);
  }

  unitBarracksLevel(unit: string): number {
    return Number(this.units[unit].barracks_level ?? 1);
  }

  unitBonus(unit: string, against: string): number {
    return Number(this.units[unit].bonus?.[against] ?? 1.0);
  }
}
