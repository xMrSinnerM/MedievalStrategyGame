// A player's armies sent against robber baron camps: they march out on a
// timer, fight, and come home with what they can carry. A port of the march
// code in scripts/core/economy.gd, working on plain data so the server can
// keep one of these per player.

import { attackCamp, isReady, type CampData } from "./baron_camp.ts";
import { BaronRules } from "./baron_rules.ts";
import type { Side } from "./battle.ts";
import { CastleState } from "./castle_state.ts";
import { godotHash, type Dict } from "./util.ts";

export interface March {
  id: number;
  camp: string;
  army: Dict;
  depart: number;
  arrive: number;
  back: number;
  state: "out" | "home" | "done";
  survivors: Dict;
  loot: Dict;
}

export interface Report {
  march: number;
  camp: string;
  name: string;
  at: number;
  empty: boolean;
  winner: "a" | "b";
  a: Side;
  b: Side;
  spoils: Dict;
  level: number;
  leveled: boolean;
  new_level: number;
  defeats: number;
  needed: number;
}

export interface Army {
  castle: CastleState;
  camps: CampData[];
  marches: March[];
  nextMarch: number;
  home: [number, number];
}

export function marchTimeTo(world: Army, rules: BaronRules, camp: CampData): number {
  const dx = camp.position[0] - world.home[0];
  const dy = camp.position[1] - world.home[1];
  return rules.marchTime(Math.sqrt(dx * dx + dy * dy));
}

export function checkAttack(world: Army, campId: string, army: Dict, now: number): string {
  const camp = world.camps.find((c) => c.id === campId);
  if (camp === undefined) return "No such camp.";
  if (!isReady(camp, now)) return "The camp is still rebuilding.";
  let total = 0;
  for (const unit of Object.keys(army)) {
    const n = army[unit];
    if (!world.castle.rules.hasUnit(unit)) return "Unknown unit.";
    if (!Number.isInteger(n) || n < 0 || n > (world.castle.troops[unit] ?? 0)) return "Your garrison doesn't have that many soldiers.";
    total += n;
  }
  if (total <= 0) return "Choose some soldiers to send.";
  return "";
}

/** Sends soldiers from the garrison against a camp. Returns "" or why not. */
export function sendAttack(world: Army, rules: BaronRules, campId: string, army: Dict, now: number): string {
  world.castle.advanceTo(now);
  const why = checkAttack(world, campId, army, now);
  if (why !== "") return why;
  const sent: Dict = {};
  for (const unit of Object.keys(army)) {
    if (army[unit] > 0) {
      sent[unit] = army[unit];
      world.castle.troops[unit] -= army[unit];
    }
  }
  const travel = marchTimeTo(world, rules, world.camps.find((c) => c.id === campId)!);
  world.marches.push({ id: world.nextMarch, camp: campId, army: sent, depart: now, arrive: now + travel,
    back: now + 2 * travel, state: "out", survivors: {}, loot: {} });
  world.nextMarch += 1;
  return "";
}

/**
 * Fights the battles and brings home the armies whose time has come, in
 * order, running the castle's economy up to each moment so loot lands in
 * the storage as it was then. Returns a report for every battle fought.
 */
export function advanceMarches(world: Army, rules: BaronRules, t: number): Report[] {
  const events: [number, March, "fight" | "home"][] = [];
  for (const m of world.marches) {
    if (m.state === "out" && t >= m.arrive) events.push([m.arrive, m, "fight"]);
    if ((m.state === "out" || m.state === "home") && t >= m.back) events.push([m.back, m, "home"]);
  }
  events.sort((x, y) => x[0] - y[0] || x[1].id - y[1].id);
  const reports: Report[] = [];
  for (const [at, m, kind] of events) {
    if (kind === "fight") reports.push(fightCamp(world, rules, m));
    else comeHome(world, m, at);
  }
  world.marches = world.marches.filter((m) => m.state !== "done");
  return reports;
}

export function troopsAway(world: Army): number {
  let n = 0;
  for (const m of world.marches) {
    const side = m.state === "out" ? m.army : m.survivors;
    for (const unit of Object.keys(side)) n += side[unit];
  }
  return n;
}

function fightCamp(world: Army, rules: BaronRules, m: March): Report {
  const camp = world.camps.find((c) => c.id === m.camp);
  m.state = "home";
  const report: Report = { march: m.id, camp: m.camp, name: camp?.name ?? "", at: m.arrive, empty: false,
    winner: "a", a: {}, b: {}, spoils: {}, level: camp?.level ?? 0, leveled: false, new_level: camp?.level ?? 0,
    defeats: camp?.defeats ?? 0, needed: camp ? rules.defeatsNeeded(camp.level) : 0 };
  if (camp === undefined || !isReady(camp, m.arrive)) {
    // The camp was beaten by an earlier army and is still in ashes.
    m.survivors = m.army;
    report.empty = true;
    return report;
  }
  const result = attackCamp(camp, rules, world.castle.rules, m.army, m.id * 7919 + godotHash(m.camp), m.arrive);
  m.survivors = result.survivors;
  m.loot = result.loot;
  return { ...report, winner: result.winner, a: result.a, b: result.b, spoils: result.loot, level: result.level,
    leveled: result.leveled, new_level: camp.level, defeats: camp.defeats, needed: rules.defeatsNeeded(camp.level) };
}

function comeHome(world: Army, m: March, at: number): void {
  const castle = world.castle;
  castle.advanceTo(at);
  for (const unit of Object.keys(m.survivors)) castle.troops[unit] = (castle.troops[unit] ?? 0) + m.survivors[unit];
  const cap = castle.storageCapacity();
  for (const r of Object.keys(m.loot)) {
    const have = castle.resources[r] ?? 0;
    castle.resources[r] = Math.max(have, Math.min(cap, have + m.loot[r]));
  }
  m.state = "done";
}
