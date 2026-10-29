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
  /** Siege tools (data/units.json "tools"), and how many fit on each wall by level. */
  tools: Record<string, Json> = {};
  toolSlotTable: number[] = [];
  /** The academy's studies (data/buildings.json "research"). */
  studies: Record<string, Json> = {};
  branches: Record<string, string> = {};
  studyCostGrowth = 1.8;
  studyTimeGrowth = 2.0;
  timePerAcademyLevel = 0.94;
  /** Public order: production change per point, and its limits. */
  orderPerPoint = 0.002;
  orderMaxBonus = 0.3;
  orderMaxPenalty = 0.3;

  constructor(buildings: Json, units: Json) {
    this.resources = (buildings.resources ?? []).map(String);
    this.gridSize = Number(buildings.grid_size ?? 24);
    this.start = buildings.start ?? {};
    this.types = buildings.buildings ?? {};
    this.units = units.units ?? {};
    this.queueSize = Number(units.queue_size ?? 5);
    this.maxBatch = Number(units.max_batch ?? 50);
    this.timePerBarracksLevel = Number(units.time_per_barracks_level ?? 0.92);
    this.tools = units.tools ?? {};
    this.toolSlotTable = (units.tool_slots ?? [0]).map(Number);
    const research = buildings.research ?? {};
    this.studies = research.studies ?? {};
    this.branches = research.branches ?? {};
    this.studyCostGrowth = Number(research.cost_growth ?? 1.8);
    this.studyTimeGrowth = Number(research.time_growth ?? 2.0);
    this.timePerAcademyLevel = Number(research.time_per_academy_level ?? 0.94);
    const order = buildings.public_order ?? {};
    this.orderPerPoint = Number(order.per_point ?? 0.002);
    this.orderMaxBonus = Number(order.max_bonus ?? 0.3);
    this.orderMaxPenalty = Number(order.max_penalty ?? 0.3);
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

  isDecoration(type: string): boolean {
    return this.types[type].category === "decoration";
  }

  /** Public order this building gives (decorations, the keep) or takes away (crowding). */
  order(type: string, level: number): number {
    const def = this.types[type];
    if (level <= 0 || !("order" in def)) return 0;
    return round(Number(def.order) * Math.pow(Number(def.order_growth ?? 1.0), level - 1));
  }

  /** How much more (or less, below zero) every resource is produced at this public order. */
  orderBonus(publicOrder: number): number {
    return clamp(publicOrder * this.orderPerPoint, -this.orderMaxPenalty, this.orderMaxBonus);
  }

  builders(keepLevel: number): number {
    const table: number[] = this.types.keep?.builders ?? [1];
    return Number(table[clamp(keepLevel - 1, 0, table.length - 1)]);
  }

  maxLevel(type: string, keepLevel: number): number {
    const cap = Number(this.types[type].max_level ?? 10);
    return type === "keep" ? cap : Math.min(cap, keepLevel * 2);
  }

  /** The keep level a first building of this type needs. */
  requiredKeep(type: string): number {
    return Number(this.types[type].keep_level ?? 1);
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

  // --- Siege tools ----------------------------------------------------------

  hasTool(tool: string): boolean {
    return Object.hasOwn(this.tools, tool);
  }

  /** "attack" or "defence". */
  toolSide(tool: string): string {
    return String(this.tools[tool].side ?? "attack");
  }

  toolCost(tool: string, count = 1): Dict {
    const out: Dict = {};
    const cost = this.tools[tool].cost ?? {};
    for (const r of Object.keys(cost)) out[r] = Number(cost[r]) * count;
    return out;
  }

  /** Seconds to build one tool; each workshop level above 1 builds faster. */
  toolTime(tool: string, workshopLevel: number): number {
    return round(Number(this.tools[tool].time ?? 30) *
      Math.pow(this.timePerBarracksLevel, Math.max(workshopLevel - 1, 0)));
  }

  toolWorkshopLevel(tool: string): number {
    return Number(this.tools[tool].workshop_level ?? 1);
  }

  /** Whether the tool can be used at this wall. */
  toolFits(tool: string, wall: string): boolean {
    const walls = this.tools[tool].walls;
    return walls === undefined || walls.includes(wall);
  }

  toolEffect(tool: string, effect: string): number {
    return Number(this.tools[tool].effect?.[effect] ?? 0);
  }

  /** How many tools fit on one wall: attack tools by keep level, defence tools by wall level. */
  toolSlots(level: number): number {
    if (level < 1) return 0;
    return this.toolSlotTable[clamp(level - 1, 0, this.toolSlotTable.length - 1)];
  }

  // --- Research -------------------------------------------------------------

  hasStudy(study: string): boolean {
    return Object.hasOwn(this.studies, study);
  }

  studyName(study: string): string {
    return String(this.studies[study].name ?? study);
  }

  studyMaxLevel(study: string): number {
    return Number(this.studies[study].max_level ?? 5);
  }

  /** The academy level that unlocks this study. */
  studyAcademyLevel(study: string): number {
    return Number(this.studies[study].academy_level ?? 1);
  }

  /** Other studies (id -> level) this one needs first. */
  studyRequires(study: string): Dict {
    return this.studies[study].requires ?? {};
  }

  /** What each level adds: effect -> amount. */
  studyEffects(study: string): Dict {
    return this.studies[study].effects ?? {};
  }

  studyCost(study: string, level: number): Dict {
    const def = this.studies[study];
    const factor = Math.pow(this.studyCostGrowth, level - 1);
    const out: Dict = {};
    for (const r of Object.keys(def.cost ?? {})) out[r] = round(Number(def.cost[r]) * factor);
    return out;
  }

  /** Seconds to research `level`; each academy level above 1 researches faster. */
  studyTime(study: string, level: number, academyLevel: number): number {
    return round(Number(this.studies[study].time ?? 300) * Math.pow(this.studyTimeGrowth, level - 1) *
      Math.pow(this.timePerAcademyLevel, Math.max(academyLevel - 1, 0)));
  }
}
