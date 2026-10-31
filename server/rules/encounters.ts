// Random map encounters: bandit camps, merchant caravans and treasure sites
// that come and go along the roads. Which ones are on the map is worked out
// from the time alone, so the game and the server see the same ones. Each
// castle can win each encounter once. A port of
// scripts/economy/encounter_rules.gd; the numbers are in data/encounters.json.

import { fight, type FightResult } from "./battle.ts";
import type { CastleState } from "./castle_state.ts";
import { give, type Reward } from "./quests.ts";
import { Rng } from "./rng.ts";
import { clamp, godotHash, round, type Dict } from "./util.ts";

const KINDS = ["bandits", "caravan", "treasure"] as const;
const SHARES: Dict = { quarter: 0.25, half: 0.5, all: 1.0 };

export interface EncounterData {
  window_hours: number;
  count: number;
  scale: number[];
  kinds: Dict;
  bandits: { name: string; army: Dict[]; loot: Dict; chest: string; chest_chance: number };
  caravan: { name: string; trades: { give: Dict; get: Dict }[] };
  treasure: { name: string; diggers: number; cost: Dict; gold: number; chests: { kind: string; weight: number }[] };
}

/** The encounter rules with the roads they stand on (data/roads.json point lists). */
export interface EncounterRules {
  data: EncounterData;
  roads: [number, number][][];
}

export interface Encounter {
  id: string;
  slot: number;
  kind: (typeof KINDS)[number];
  road: number;
  at: number;
  variant: number;
  start: number;
  end: number;
}

// deno-lint-ignore no-explicit-any
export function encounterRules(data: any, roads: any): EncounterRules {
  return { data, roads: (roads.roads ?? []).map((r: { points: [number, number][] }) => r.points).filter((p: unknown[]) => p.length >= 2) };
}

function windowSecs(rules: EncounterRules): number {
  return rules.data.window_hours * 3600;
}

function scaled(rules: EncounterRules, base: Dict, keep: number): Dict {
  const mult = rules.data.scale[clamp(keep, 1, rules.data.scale.length) - 1];
  const out: Dict = {};
  for (const [r, n] of Object.entries(base)) out[r] = round(n * mult);
  return out;
}

/** The encounter slot `slot` holds in its window `w`. */
export function makeEncounter(rules: EncounterRules, slot: number, w: number): Encounter {
  const rng = new Rng(w * 7919 + slot * 104729 + 4242);
  const weights = rules.data.kinds;
  const sum = KINDS.reduce((s, k) => s + (weights[k] ?? 0), 0);
  let roll = rng.randi() % Math.max(sum, 1);
  let kind: Encounter["kind"] = KINDS[0];
  for (const k of KINDS) {
    roll -= weights[k] ?? 0;
    if (roll < 0) {
      kind = k;
      break;
    }
  }
  const road = rng.randi() % rules.roads.length;
  // How far along the road, in thousandths of its length: the middle, away
  // from the settlements at its ends.
  const at = 300 + (rng.randi() % 401);
  const variant = rng.randi() % 1000;
  const win = windowSecs(rules);
  const start = w * win - (win * slot) / Math.max(rules.data.count, 1);
  return { id: `e${slot}-${w}`, slot, kind, road, at, variant, start, end: start + win };
}

/** The encounters on the map at time t. */
export function activeEncounters(rules: EncounterRules, t: number): Encounter[] {
  if (rules.roads.length === 0) return [];
  const win = windowSecs(rules);
  const out: Encounter[] = [];
  for (let slot = 0; slot < rules.data.count; slot++) {
    out.push(makeEncounter(rules, slot, Math.floor((t + (win * slot) / rules.data.count) / win)));
  }
  return out;
}

export function banditArmy(rules: EncounterRules, keep: number): Dict {
  const armies = rules.data.bandits.army;
  return { ...armies[clamp(keep, 1, armies.length) - 1] };
}

/** The soldiers a share of the garrison makes. */
export function sentArmy(castle: CastleState, share: unknown): Dict {
  const f = typeof share === "string" && Object.hasOwn(SHARES, share) ? SHARES[share] : 0;
  const army: Dict = {};
  for (const [unit, n] of Object.entries(castle.troops)) {
    const k = Math.floor(n * f);
    if (k > 0) army[unit] = k;
  }
  return army;
}

export function caravanTrade(rules: EncounterRules, e: Encounter, keep: number): { give: Dict; get: Dict } {
  const trades = rules.data.caravan.trades;
  const t = trades[e.variant % trades.length];
  return { give: scaled(rules, t.give, keep), get: scaled(rules, t.get, keep) };
}

/** Why this encounter can't be taken on now ("" if it can). */
export function checkEncounter(castle: CastleState, rules: EncounterRules, e: Encounter | undefined, choice: unknown): string {
  if (!e) return "That's gone from the map.";
  if (castle.encounters.done.includes(e.id)) return "You've already been there.";
  if (e.kind === "bandits" && Object.keys(sentArmy(castle, choice)).length === 0) return "Send at least one soldier.";
  if (e.kind === "caravan" && !castle.canAfford(caravanTrade(rules, e, castle.keepLevel()).give)) return "You don't have enough to trade.";
  if (e.kind === "treasure") {
    const t = rules.data.treasure;
    if (castle.troopCount() < t.diggers) return `You need ${t.diggers} soldiers at home to dig.`;
    if (!castle.canAfford(scaled(rules, t.cost, castle.keepLevel()))) return "You don't have enough food for the diggers.";
  }
  return "";
}

function record(castle: CastleState, rules: EncounterRules, id: string, t: number): void {
  const live = new Set(activeEncounters(rules, t).map((e) => e.id));
  castle.encounters.done = [...castle.encounters.done.filter((d) => live.has(d)), id];
}

export interface EncounterResult {
  error: string;
  kind?: Encounter["kind"];
  fight?: FightResult;
  won?: boolean;
  paid?: Dict;
  reward?: Reward;
}

/** Takes on an encounter. */
export function takeEncounter(castle: CastleState, rules: EncounterRules, id: unknown, choice: unknown, now: number): EncounterResult {
  const e = activeEncounters(rules, now).find((x) => x.id === id);
  const why = checkEncounter(castle, rules, e, choice);
  if (why !== "") return { error: why };
  const enc = e!;
  const keep = castle.keepLevel();
  const seed = godotHash(castle.castleName) + (Math.floor(enc.start) % 100003) + enc.slot * 31;
  if (enc.kind === "bandits") {
    const army = sentArmy(castle, choice);
    const result = fight(castle.rules, army, banditArmy(rules, keep), seed);
    for (const [unit, side] of Object.entries(result.a)) {
      castle.troops[unit] = (castle.troops[unit] ?? 0) - side.lost;
      if (castle.troops[unit] <= 0) delete castle.troops[unit];
    }
    const won = result.winner === "a";
    let reward: Reward = {};
    if (won) {
      reward = { resources: scaled(rules, rules.data.bandits.loot, keep) };
      if (new Rng(seed).randf() < rules.data.bandits.chest_chance) reward.chests = { [rules.data.bandits.chest]: 1 };
      give(castle, reward);
      record(castle, rules, enc.id, now);
    }
    return { error: "", kind: "bandits", fight: result, won, reward };
  }
  if (enc.kind === "caravan") {
    const offer = caravanTrade(rules, enc, keep);
    castle.pay(offer.give);
    const reward = { resources: offer.get };
    give(castle, reward);
    record(castle, rules, enc.id, now);
    return { error: "", kind: "caravan", paid: offer.give, reward };
  }
  const t = rules.data.treasure;
  castle.pay(scaled(rules, t.cost, keep));
  const rng = new Rng(seed);
  const sum = t.chests.reduce((s, c) => s + c.weight, 0);
  let roll = rng.randi() % Math.max(sum, 1);
  let chest = "wooden";
  for (const c of t.chests) {
    roll -= c.weight;
    if (roll < 0) {
      chest = c.kind;
      break;
    }
  }
  const reward: Reward = { resources: scaled(rules, { gold: t.gold }, keep), chests: { [chest]: 1 } };
  give(castle, reward);
  record(castle, rules, enc.id, now);
  return { error: "", kind: "treasure", reward };
}
