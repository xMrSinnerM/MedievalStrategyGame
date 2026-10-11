// One robber baron's camp. A port of scripts/economy/baron_camp.gd: every
// win raises it towards its next level, and a beaten camp rebuilds for a
// while before it can be attacked again.

import { BaronRules } from "./baron_rules.ts";
import { fight, survivors, wallFromDefense, type FightResult } from "./battle.ts";
import { BuildingRules } from "./building_rules.ts";
import type { Dict } from "./util.ts";

export interface CampData {
  id: string;
  name: string;
  position: [number, number];
  level: number;
  defeats: number;
  rebuilt_at: number;
}

export interface CampAttack extends FightResult {
  level: number;
  leveled: boolean;
  survivors: Dict;
  loot: Dict;
}

export function isReady(camp: CampData, now: number): boolean {
  return now >= camp.rebuilt_at;
}

/** Fights the camp's garrison behind its palisade and updates the camp. */
export function attackCamp(camp: CampData, rules: BaronRules, units: BuildingRules, army: Dict, seed: number, now: number): CampAttack {
  const result = fight(units, army, rules.garrison(camp.level), seed, wallFromDefense(rules.palisade(camp.level)));
  const out: CampAttack = { ...result, level: camp.level, leveled: false, survivors: survivors(result.a), loot: {} };
  if (result.winner !== "a") return out;
  out.loot = carried(rules.loot(camp.level), rules.carry(out.survivors));
  camp.rebuilt_at = now + rules.rebuildTime(camp.level);
  camp.defeats += 1;
  if (camp.defeats >= rules.defeatsNeeded(camp.level) && camp.level < rules.maxLevel) {
    camp.level += 1;
    camp.defeats = 0;
    out.leveled = true;
  }
  return out;
}

function carried(stock: Dict, capacity: number): Dict {
  let all = 0;
  for (const r of Object.keys(stock)) all += stock[r];
  const share = all <= capacity ? 1 : capacity / all;
  const out: Dict = {};
  for (const r of Object.keys(stock)) out[r] = Math.floor(stock[r] * share);
  return out;
}
