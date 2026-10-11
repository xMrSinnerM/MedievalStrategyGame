// Auto-resolves a fight between two armies (unit -> soldiers). A port of
// Battle.fight() and its helpers in scripts/economy/battle.gd; the same
// armies, seed and wall give the same result as in the game.

import { BuildingRules } from "./building_rules.ts";
import { Rng } from "./rng.ts";
import { round, type Dict } from "./util.ts";

export const DAMAGE = 0.3;
export const ROUT = 0.35;
export const MAX_ROUNDS = 12;
export const ODDS_SAMPLES = 40;
export const WALL_MAX = 1.5;
export const WALL_HALF = 200.0;

export type Side = Record<string, { start: number; lost: number }>;

export interface FightResult {
  winner: "a" | "b";
  rounds: number;
  a: Side;
  b: Side;
}

export function fight(rules: BuildingRules, a: Dict, b: Dict, seed: number, wall = 1.0): FightResult {
  const rng = new Rng(seed);
  const leftA = floats(a);
  const leftB = floats(b);
  const startA = total(leftA);
  const startB = total(leftB);
  let rounds = 0;
  while (rounds < MAX_ROUNDS && startA > 0 && startB > 0) {
    rounds += 1;
    const hitsB = casualties(rules, leftA, leftB, rng.randfRange(0.8, 1.2), wall);
    const hitsA = casualties(rules, leftB, leftA, rng.randfRange(0.8, 1.2), 1.0);
    apply(leftA, hitsA);
    apply(leftB, hitsB);
    if (total(leftA) <= startA * ROUT || total(leftB) <= startB * ROUT) break;
  }
  const shareA = startA > 0 ? total(leftA) / startA : 0;
  const shareB = startB > 0 ? total(leftB) / startB : 0;
  return { winner: shareA > shareB ? "a" : "b", rounds, a: losses(a, leftA), b: losses(b, leftB) };
}

export function wallFromDefense(d: number): number {
  return 1.0 + WALL_MAX * d / (d + WALL_HALF);
}

export function odds(rules: BuildingRules, a: Dict, b: Dict, seed = 1, wall = 1.0): number {
  if (total(floats(a)) <= 0) return 0;
  let wins = 0;
  for (let k = 0; k < ODDS_SAMPLES; k++) if (fight(rules, a, b, seed + k, wall).winner === "a") wins += 1;
  return wins / ODDS_SAMPLES;
}

export function survivors(side: Side): Dict {
  const out: Dict = {};
  for (const unit of Object.keys(side)) {
    const n = side[unit].start - side[unit].lost;
    if (n > 0) out[unit] = n;
  }
  return out;
}

export function lostCount(side: Side): number {
  return Object.values(side).reduce((n, s) => n + s.lost, 0);
}

function casualties(rules: BuildingRules, attackers: Dict, defenders: Dict, luck: number, wall: number): Dict {
  const out: Dict = {};
  const all = total(defenders);
  if (all <= 0) return out;
  for (const u of Object.keys(attackers)) {
    const power = attackers[u] * rules.unitStat(u, "attack") * DAMAGE * luck;
    for (const t of Object.keys(defenders)) {
      if (defenders[t] <= 0) continue;
      const share = defenders[t] / all;
      out[t] = (out[t] ?? 0) + power * share * rules.unitBonus(u, t) / Math.max(rules.unitStat(t, "defense") * wall, 1.0);
    }
  }
  return out;
}

function apply(army: Dict, hits: Dict): void {
  for (const t of Object.keys(hits)) army[t] = Math.max(army[t] - hits[t], 0);
}

function floats(army: Dict): Dict {
  const out: Dict = {};
  for (const u of Object.keys(army)) if (army[u] > 0) out[u] = Number(army[u]);
  return out;
}

function total(army: Dict): number {
  let n = 0;
  for (const u of Object.keys(army)) n += army[u];
  return n;
}

function losses(start: Dict, left: Dict): Side {
  const out: Side = {};
  for (const u of Object.keys(start)) {
    if (start[u] <= 0) continue;
    const remaining = Math.trunc(round(left[u] ?? 0));
    const s = Math.trunc(start[u]);
    out[u] = { start: s, lost: Math.min(Math.max(s - remaining, 0), s) };
  }
  return out;
}
