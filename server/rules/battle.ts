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
export const WALLS = ["left", "front", "right"] as const;
export type Wall = typeof WALLS[number];
export type Layout = Record<Wall | "courtyard", number>;
export const DEFAULT_LAYOUT: Layout = { left: 25, front: 35, right: 25, courtyard: 15 };
export const ATTACK_SPLIT: Record<string, number> = { left: 30, front: 40, right: 30 };
export const WAVES_BY_KEEP: [number, number][] = [[1, 1], [2, 2], [4, 3]];
export const WALL_SEED = 101;
export const COURTYARD_SEED = 997;
export const COURTYARD_BONUS = 1.5;

export type Side = Record<string, { start: number; lost: number }>;

export interface FightResult {
  winner: "a" | "b";
  rounds: number;
  a: Side;
  b: Side;
}

/**
 * `wall` multiplies side b's defence; `powerA` and `powerB` multiply the
 * damage each side deals (siege tools, wallMods()).
 */
export function fight(rules: BuildingRules, a: Dict, b: Dict, seed: number, wall = 1.0, powerA = 1.0, powerB = 1.0): FightResult {
  const rng = new Rng(seed);
  const leftA = floats(a);
  const leftB = floats(b);
  const startA = total(leftA);
  const startB = total(leftB);
  let rounds = 0;
  while (rounds < MAX_ROUNDS && startA > 0 && startB > 0) {
    rounds += 1;
    const hitsB = casualties(rules, leftA, leftB, rng.randfRange(0.8, 1.2) * powerA, wall);
    const hitsA = casualties(rules, leftB, leftA, rng.randfRange(0.8, 1.2) * powerB, 1.0);
    apply(leftA, hitsA);
    apply(leftB, hitsB);
    if (total(leftA) <= startA * ROUT || total(leftB) <= startB * ROUT) break;
  }
  const shareA = startA > 0 ? total(leftA) / startA : 0;
  const shareB = startB > 0 ? total(leftB) / startB : 0;
  return { winner: shareA > shareB ? "a" : "b", rounds, a: losses(a, leftA), b: losses(b, leftB) };
}

/** One wave of an attack: soldiers for each wall. */
export type Wave = Partial<Record<Wall, Dict>>;

/** Siege tools at each wall (data/units.json "tools"). */
export type Tools = Partial<Record<Wall, Dict>>;

/**
 * The attackers' tools (a) and the defenders' (b) in a siege, and what the
 * attackers' commander (lead_a) and the defenders' castellan (lead_b) add
 * (stat -> share, GearRules.effects() in gear.ts).
 */
export interface SiegeTools {
  a?: Tools;
  b?: Tools;
  lead_a?: Dict;
  lead_b?: Dict;
}

/** What the tools at one wall do to its fights: the wall's bonus and each side's damage. */
export function wallMods(rules: BuildingRules, wall: number, a: Dict, b: Dict, leadA: Dict = {}, leadB: Dict = {}):
  { wall: number; a: number; b: number } {
  let cut = 0;
  let shield = 0;
  let moat = 0;
  let volley = 0;
  let scald = 0;
  for (const t of Object.keys(rules.tools)) {
    const na = Math.trunc(a[t] ?? 0);
    const nb = Math.trunc(b[t] ?? 0);
    if (na > 0) {
      cut += na * rules.toolEffect(t, "wall_cut");
      shield += na * rules.toolEffect(t, "shield");
    }
    if (nb > 0) {
      moat += nb * rules.toolEffect(t, "moat");
      volley += nb * rules.toolEffect(t, "volley");
      scald += nb * rules.toolEffect(t, "scald");
    }
  }
  cut += leadA.wall_cut ?? 0;
  moat += leadB.wall_bonus ?? 0;
  const w = cut === 0 && moat === 0 ? wall : (1 + (wall - 1) * (1 - Math.min(cut, 1))) * (1 + moat);
  return { wall: w, a: (1 - Math.min(scald, 0.5)) * (1 + (leadA.wall_attack ?? 0)),
    b: (1 - Math.min(shield, 0.5)) * (1 + volley) * (1 + (leadB.wall_defence ?? 0)) };
}

/** Every tool in a set of walls' tools, by tool. */
export function toolsTotal(tools: Tools): Dict {
  const out: Dict = {};
  for (const w of WALLS) add(out, tools[w] ?? {});
  return out;
}

/**
 * Checks siege tools for each wall: tools of `side` ("attack" or
 * "defence") that fit their wall, at most `slots` a wall and no more than
 * `stock` has. Returns them without empty walls, or why not.
 */
export function checkTools(rules: BuildingRules, tools: unknown, side: string, slots: number, stock: Dict): Tools | string {
  if (tools === undefined || tools === null) return {};
  if (typeof tools !== "object" || Array.isArray(tools)) return "Bad tools.";
  const out: Tools = {};
  for (const [w, set] of Object.entries(tools as Record<string, unknown>)) {
    if (!(WALLS as readonly string[]).includes(w)) return "Bad tools.";
    if (set === null || typeof set !== "object" || Array.isArray(set)) return "Bad tools.";
    const clean: Dict = {};
    let n = 0;
    for (const [tool, count] of Object.entries(set as Record<string, unknown>)) {
      if (!rules.hasTool(tool) || rules.toolSide(tool) !== side) return "Unknown siege tool.";
      if (typeof count !== "number" || !Number.isInteger(count) || count < 0) return "Bad tools.";
      if (count === 0) continue;
      if (!rules.toolFits(tool, w)) return `${rules.tools[tool].name ?? tool} can't be used at the ${w} wall.`;
      clean[tool] = count;
      n += count;
    }
    if (n > slots) return slots === 0 ? "No siege tools fit there yet." : `Only ${slots} siege tools fit on each wall.`;
    if (n > 0) out[w as Wall] = clean;
  }
  const total = toolsTotal(out);
  for (const tool of Object.keys(total)) if (total[tool] > (stock[tool] ?? 0)) return "You don't have that many siege tools.";
  return out;
}

export type WallFight = { wave: number; open: true } | { wave: number; winner: "a" | "b"; a: Side; b: Side };

export interface SiegeResult extends FightResult {
  walls: Record<Wall, { broken: boolean; fights: WallFight[] }>;
  courtyard: Record<string, never> | { open: true } | { winner: "a" | "b"; a: Side; b: Side };
  waves: number;
  /** With siege tools: each side's at each wall, and the defence tools lost with their walls. */
  tools?: { a: Tools; b: Tools; lost: Tools };
}

/**
 * Storms a castle or camp in waves. A port of Battle.siege() in
 * scripts/economy/battle.gd: the defenders stand on the walls and in the
 * courtyard by `layout`; each wave fights each wall's defenders behind the
 * wall, and attackers who break a wall go on to fight the courtyard (the
 * reserve plus that wall's last defenders), who make their last stand around
 * the keep with the wall's bonus times COURTYARD_BONUS.
 */
export function siege(rules: BuildingRules, waves: Wave[], defenders: Dict, layout: Layout, seed: number, wall = 1.0,
  tools: SiegeTools = {}): SiegeResult {
  const posts = split(defenders, layout, ["left", "right", "courtyard", "front"]);
  const sent: Dict = {};
  const home: Dict = {};
  const through: Dict = {};
  const walls = {} as SiegeResult["walls"];
  let rounds = 0;
  let brokenAny = false;
  let yard = posts.courtyard;
  const holding: Dict = {};
  WALLS.forEach((w, i) => {
    let held = posts[w];
    const fights: WallFight[] = [];
    let broken = false;
    const mods = wallMods(rules, wall, tools.a?.[w] ?? {}, tools.b?.[w] ?? {}, tools.lead_a, tools.lead_b);
    waves.forEach((wave, k) => {
      const troops = ints(wave[w] ?? {});
      if (Object.keys(troops).length === 0) return;
      add(sent, troops);
      if (broken || Object.keys(held).length === 0) {
        broken = true;
        add(through, troops);
        fights.push({ wave: k, open: true });
        return;
      }
      const r = fight(rules, troops, held, seed + WALL_SEED * (i + 1) + k, mods.wall, mods.a, mods.b);
      rounds += r.rounds;
      held = survivors(r.b);
      fights.push({ wave: k, winner: r.winner, a: r.a, b: r.b });
      if (r.winner === "a") {
        broken = true;
        add(through, survivors(r.a));
      } else {
        add(home, survivors(r.a));
      }
    });
    walls[w] = { broken, fights };
    if (broken) {
      brokenAny = true;
      add(yard, held);
    } else {
      add(holding, held);
    }
  });
  let winner: "a" | "b" = "b";
  let courtyard: SiegeResult["courtyard"] = {};
  if (brokenAny && Object.keys(through).length > 0) {
    if (Object.keys(yard).length === 0) {
      winner = "a";
      courtyard = { open: true };
      add(home, through);
    } else {
      const r = fight(rules, through, yard, seed + COURTYARD_SEED, wall * COURTYARD_BONUS,
        1 + (tools.lead_a?.yard_attack ?? 0), 1 + (tools.lead_b?.yard_defence ?? 0));
      rounds += r.rounds;
      winner = r.winner;
      courtyard = { winner: r.winner, a: r.a, b: r.b };
      yard = survivors(r.b);
      add(home, survivors(r.a));
    }
  }
  add(holding, yard);
  const result: SiegeResult = { winner, rounds, a: kept(sent, home), b: kept(ints(defenders), holding), walls, courtyard, waves: waves.length };
  const a = cleanTools(tools.a ?? {});
  const b = cleanTools(tools.b ?? {});
  if (Object.keys(a).length > 0 || Object.keys(b).length > 0) {
    // Attack tools are used up; defence tools are lost with their wall.
    const lost: Tools = {};
    for (const w of WALLS) if (walls[w].broken && b[w] !== undefined) lost[w] = { ...b[w] };
    result.tools = { a, b, lost };
  }
  return result;
}

export function siegeOdds(rules: BuildingRules, waves: Wave[], defenders: Dict, layout: Layout, seed = 1, wall = 1.0,
  tools: SiegeTools = {}): number {
  if (!waves.some((wave) => Object.values(wave).some((army) => Object.keys(ints(army ?? {})).length > 0))) return 0;
  let wins = 0;
  for (let k = 0; k < ODDS_SAMPLES; k++) if (siege(rules, waves, defenders, layout, seed + k, wall, tools).winner === "a") wins += 1;
  return wins / ODDS_SAMPLES;
}

function cleanTools(tools: Tools): Tools {
  const out: Tools = {};
  for (const w of WALLS) {
    const set = ints(tools[w] ?? {});
    if (Object.keys(set).length > 0) out[w] = set;
  }
  return out;
}

/** One wave with the army spread over the walls by ATTACK_SPLIT. */
export function autoWaves(army: Dict): Wave[] {
  return [split(army, ATTACK_SPLIT, ["left", "right", "front"])];
}

export function wavesForKeep(keep: number): number {
  let n = 1;
  for (const [from, waves] of WAVES_BY_KEEP) if (keep >= from) n = waves;
  return n;
}

/** Spreads an army over `order`'s keys by percentage, rounding down; the last key gets the rest. */
export function split(army: Dict, shares: Record<string, number>, order: string[]): Record<string, Dict> {
  const out: Record<string, Dict> = {};
  for (const key of order) out[key] = {};
  for (const u of Object.keys(army)) {
    const n = Math.trunc(army[u]);
    if (n <= 0) continue;
    let left = n;
    order.forEach((key, i) => {
      let part = i === order.length - 1 ? left : Math.floor(n * Math.trunc(shares[key] ?? 0) / 100);
      part = Math.min(part, left);
      left -= part;
      if (part > 0) out[key][u] = part;
    });
  }
  return out;
}

/**
 * Checks waves sent with an attack: 1 to `max` of them, each soldiers for
 * some of the walls. Returns them without empty walls, or why not. Whether
 * the garrison has the soldiers is checked on their sum (wavesArmy()).
 */
export function checkWaves(waves: unknown, max: number, hasUnit: (unit: string) => boolean): Wave[] | string {
  if (!Array.isArray(waves) || waves.length === 0) return "Bad waves.";
  if (waves.length > max) return max === 1 ? "Upgrade your keep to send more than one wave." : `Your keep allows ${max} waves.`;
  const out: Wave[] = [];
  for (const wave of waves) {
    if (wave === null || typeof wave !== "object" || Array.isArray(wave)) return "Bad waves.";
    const clean: Wave = {};
    for (const [w, army] of Object.entries(wave as Record<string, unknown>)) {
      if (!(WALLS as readonly string[]).includes(w)) return "Bad waves.";
      if (army === null || typeof army !== "object" || Array.isArray(army)) return "Bad waves.";
      const troops: Dict = {};
      for (const [unit, n] of Object.entries(army as Record<string, unknown>)) {
        if (!hasUnit(unit)) return "Unknown unit.";
        if (typeof n !== "number" || !Number.isInteger(n) || n < 0) return "Bad waves.";
        if (n > 0) troops[unit] = n;
      }
      if (Object.keys(troops).length > 0) clean[w as Wall] = troops;
    }
    out.push(clean);
  }
  return out;
}

/** Every soldier in the waves, by unit. */
export function wavesArmy(waves: Wave[]): Dict {
  const out: Dict = {};
  for (const wave of waves) for (const army of Object.values(wave)) add(out, army ?? {});
  return out;
}

/** "" if `layout` is a valid defence layout, otherwise why not. */
export function checkLayout(layout: unknown): string {
  if (layout === null || typeof layout !== "object" || Array.isArray(layout)) return "Bad layout.";
  const keys = Object.keys(DEFAULT_LAYOUT);
  if (Object.keys(layout).length !== keys.length) return "Bad layout.";
  let sum = 0;
  for (const key of keys) {
    const v = (layout as Record<string, unknown>)[key];
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > 100) return "Bad layout.";
    sum += v;
  }
  return sum === 100 ? "" : "The walls and courtyard must add up to 100%.";
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

function ints(army: Dict): Dict {
  const out: Dict = {};
  for (const u of Object.keys(army)) if (Math.trunc(army[u]) > 0) out[u] = Math.trunc(army[u]);
  return out;
}

function add(to: Dict, army: Dict): void {
  for (const u of Object.keys(army)) if (Math.trunc(army[u]) > 0) to[u] = (to[u] ?? 0) + Math.trunc(army[u]);
}

function kept(start: Dict, left: Dict): Side {
  const out: Side = {};
  for (const u of Object.keys(start)) out[u] = { start: start[u], lost: start[u] - Math.min(left[u] ?? 0, start[u]) };
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
