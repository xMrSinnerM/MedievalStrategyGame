// Weather on the world map: rain and storm cells that drift across it.
// Which cells are out is worked out from the time alone, so the game and the
// server agree. An army marching out through rain or a storm takes longer.
// A port of scripts/economy/weather_rules.gd (without the time of day, which
// is only light); the numbers are in data/weather.json.

import { Rng } from "./rng.ts";

const KINDS = ["clear", "rain", "storm"] as const;

export interface WeatherRules {
  window_hours: number;
  count: number;
  area: [number, number];
  radius: [number, number];
  drift: number;
  kinds: Record<string, { weight: number; name: string; slow: number }>;
  day_hours: number;
}

export interface Cell {
  id: string;
  slot: number;
  kind: (typeof KINDS)[number];
  x: number;
  z: number;
  dx: number;
  dz: number;
  radius: number;
  start: number;
  end: number;
}

/** The cell slot `slot` holds in its window `w`. */
export function makeCell(rules: WeatherRules, slot: number, w: number): Cell {
  const rng = new Rng(w * 6211 + slot * 92821 + 777);
  const weight = (k: string) => rules.kinds[k]?.weight ?? 0;
  const sum = KINDS.reduce((s, k) => s + weight(k), 0);
  let roll = rng.randi() % Math.max(sum, 1);
  let kind: Cell["kind"] = KINDS[0];
  for (const k of KINDS) {
    roll -= weight(k);
    if (roll < 0) {
      kind = k;
      break;
    }
  }
  const [lo, hi] = rules.area;
  const x = lo + (rng.randi() % Math.max(1, hi - lo + 1));
  const z = lo + (rng.randi() % Math.max(1, hi - lo + 1));
  const dx = (rng.randi() % (2 * rules.drift + 1)) - rules.drift;
  const dz = (rng.randi() % (2 * rules.drift + 1)) - rules.drift;
  const radius = rules.radius[0] + (rng.randi() % Math.max(1, rules.radius[1] - rules.radius[0] + 1));
  const win = rules.window_hours * 3600;
  const start = w * win - (win * slot) / Math.max(rules.count, 1);
  return { id: `w${slot}-${w}`, slot, kind, x, z, dx, dz, radius, start, end: start + win };
}

/** The cells on the map at time t, clear ones too. */
export function activeCells(rules: WeatherRules, t: number): Cell[] {
  const win = rules.window_hours * 3600;
  const out: Cell[] = [];
  for (let slot = 0; slot < rules.count; slot++) out.push(makeCell(rules, slot, Math.floor((t + (win * slot) / rules.count) / win)));
  return out;
}

/** Where the cell is at time t: it drifts evenly over its window. */
export function cellCentre(rules: WeatherRules, cell: Cell, t: number): [number, number] {
  const f = Math.min(Math.max((t - cell.start) / (rules.window_hours * 3600), 0), 1);
  return [cell.x + cell.dx * f, cell.z + cell.dz * f];
}

function near(c: [number, number], a: [number, number], b: [number, number]): number {
  const [abx, abz] = [b[0] - a[0], b[1] - a[1]];
  const len2 = abx * abx + abz * abz;
  const f = len2 <= 0 ? 0 : Math.min(Math.max(((c[0] - a[0]) * abx + (c[1] - a[1]) * abz) / len2, 0), 1);
  return Math.hypot(c[0] - (a[0] + abx * f), c[1] - (a[1] + abz * f));
}

/** The worst cell an army setting off at t marches through, if any. */
export function marchCell(rules: WeatherRules, from: [number, number], to: [number, number], t: number): Cell | undefined {
  let worst: Cell | undefined;
  let worstSlow = 0;
  for (const cell of activeCells(rules, t)) {
    const slow = rules.kinds[cell.kind]?.slow ?? 0;
    if (slow > worstSlow && near(cellCentre(rules, cell, t), from, to) <= cell.radius) {
      worst = cell;
      worstSlow = slow;
    }
  }
  return worst;
}

/** Multiplier on a march's time for the weather on its way (1 = none, or no weather rules). */
export function marchSlow(rules: WeatherRules | undefined, from: [number, number], to: [number, number], t: number): number {
  if (rules === undefined) return 1;
  const cell = marchCell(rules, from, to, t);
  return 1 + (cell ? rules.kinds[cell.kind].slow : 0);
}
