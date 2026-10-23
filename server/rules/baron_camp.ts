// One robber baron's camp. A port of scripts/economy/baron_camp.gd: every
// win raises it towards its next level, and a beaten camp rebuilds for a
// while before it can be attacked again.

import { BaronRules } from "./baron_rules.ts";
import { autoWaves, DEFAULT_LAYOUT, siege, survivors, wallFromDefense, type SiegeResult, type Tools, type Wave } from "./battle.ts";
import { BuildingRules } from "./building_rules.ts";
import type { Dict } from "./util.ts";

export interface CampData {
  id: string;
  name: string;
  position: [number, number];
  level: number;
  defeats: number;
  rebuilt_at: number;
  /** Invader camps only (online events): the start of the invasion it belongs to. */
  event?: number;
  /** Invader camps only: event points per level for a win. */
  points?: number;
  /** Invader camps only: seconds it rebuilds after a defeat. */
  rebuild?: number;
  /** A fortress (one of the old kingdoms' castles), with the fortress rules (BaronRules.forCamp()). */
  fortress?: boolean;
}

export interface CampAttack extends SiegeResult {
  level: number;
  leveled: boolean;
  survivors: Dict;
  loot: Dict;
}

export function isReady(camp: CampData, now: number): boolean {
  return now >= camp.rebuilt_at;
}

/**
 * Storms the camp's palisade with `waves` (by default the army in one wave,
 * autoWaves()) and the attackers' siege `tools`, the garrison in
 * DEFAULT_LAYOUT, and updates the camp. `lead` is what the army's commander
 * adds (gear.ts effects()): harder blows, and `loot` more carried home.
 */
export function attackCamp(camp: CampData, barons: BaronRules, units: BuildingRules, army: Dict, seed: number, now: number,
  waves?: Wave[], tools: Tools = {}, lead: Dict = {}): CampAttack {
  const rules = barons.forCamp(camp);
  const result = siege(units, waves ?? autoWaves(army), rules.garrison(camp.level), DEFAULT_LAYOUT, seed,
    wallFromDefense(rules.palisade(camp.level)), { a: tools, lead_a: lead });
  const out: CampAttack = { ...result, level: camp.level, leveled: false, survivors: survivors(result.a), loot: {} };
  if (result.winner !== "a") return out;
  const factor = barons.lootFactor(now);
  const stock: Dict = {};
  for (const [r, n] of Object.entries(rules.loot(camp.level))) stock[r] = Math.floor(n * factor);
  out.loot = carried(stock, rules.carry(out.survivors) * (1 + (lead.loot ?? 0)));
  camp.rebuilt_at = now + (camp.rebuild ?? rules.rebuildTime(camp.level));
  camp.defeats += 1;
  // An invader camp rises a level with every win.
  const needed = camp.event === undefined ? rules.defeatsNeeded(camp.level) : 1;
  if (camp.defeats >= needed && camp.level < rules.maxLevel) {
    camp.level += 1;
    camp.defeats = 0;
    out.leveled = true;
  }
  return out;
}

/** As much of `stock` as `capacity` can carry, each resource cut by the same share. */
export function carried(stock: Dict, capacity: number): Dict {
  let all = 0;
  for (const r of Object.keys(stock)) all += stock[r];
  const share = all <= capacity ? 1 : capacity / all;
  const out: Dict = {};
  for (const r of Object.keys(stock)) out[r] = Math.floor(stock[r] * share);
  return out;
}
