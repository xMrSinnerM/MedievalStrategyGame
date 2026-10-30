// A player's armies sent against robber baron camps: they march out on a
// timer, fight, and come home with what they can carry. A port of the march
// code in scripts/core/economy.gd, working on plain data so the server can
// keep one of these per player.

import { attackCamp, isReady, type CampData } from "./baron_camp.ts";
import { BaronRules } from "./baron_rules.ts";
import { checkTools, type Side, type SiegeResult, type Tools, type Wave } from "./battle.ts";
import { CastleState } from "./castle_state.ts";
import type { GearRules, Item, Lead, LeadReport } from "./gear.ts";
import { godotHash, type Dict } from "./util.ts";
import { marchSlow, type WeatherRules } from "./weather.ts";

/** Seed offset for what a beaten camp drops. */
export const DROP_SEED = 31337;

export interface March {
  id: number;
  camp: string;
  army: Dict;
  /** How the army storms the walls; without it, one wave (autoWaves()). */
  waves?: Wave[];
  /** Siege tools brought to each wall (used up in the fight). */
  tools?: Tools;
  /** The commander leading the army, with what their gear does. */
  lead?: Lead;
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
  /** How each wall and the courtyard went; absent when the camp was empty. */
  walls?: SiegeResult["walls"];
  courtyard?: SiegeResult["courtyard"];
  /** Siege tools used, when there were any. */
  tools?: SiegeResult["tools"];
  /** The commander who led the army and the xp they earned. */
  lead?: LeadReport;
  /** Gear the camp dropped; `bag_full` when there was no room for it. */
  gear?: Item;
  bag_full?: boolean;
  spoils: Dict;
  level: number;
  leveled: boolean;
  new_level: number;
  defeats: number;
  needed: number;
  /** The camp was a fortress. */
  fortress?: boolean;
  /** Invader camps: the invasion it belongs to, and the event points this win earned. */
  event?: number;
  points?: number;
  /** Ember Horde camps: the horde's run it belongs to, and the war trophies this win earned (`points` are horde points). */
  horde?: number;
  trophies?: number;
}

export interface Army {
  castle: CastleState;
  camps: CampData[];
  marches: March[];
  nextMarch: number;
  home: [number, number];
  /** Commanders and gear (data/gear.json); without them no drops or xp. */
  gear?: GearRules;
  /** Weather (data/weather.json); without it marches are never slowed. */
  weather?: WeatherRules;
}

/** How long a march to the camp takes, setting off at `now` (the weather on the way slows it). */
export function marchTimeTo(world: Army, rules: BaronRules, camp: CampData, now?: number): number {
  const dx = camp.position[0] - world.home[0];
  const dy = camp.position[1] - world.home[1];
  const slow = now === undefined ? 1 : marchSlow(world.weather, world.home, camp.position, now);
  return rules.marchTime(Math.sqrt(dx * dx + dy * dy)) * world.castle.marchFactor() * slow;
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

/**
 * Sends soldiers from the garrison against a camp, in `waves` if given, with
 * siege `tools` for its walls (taken from the store), led by `commander` (an
 * id, or none). Returns "" or why not.
 */
export function sendAttack(world: Army, rules: BaronRules, campId: string, army: Dict, now: number, waves?: Wave[],
  tools?: unknown, commander?: unknown): string {
  world.castle.advanceTo(now);
  const why = checkAttack(world, campId, army, now);
  if (why !== "") return why;
  const castle = world.castle;
  const kit = checkTools(castle.rules, tools, "attack", castle.rules.toolSlots(castle.keepLevel()), castle.tools);
  if (typeof kit === "string") return kit;
  const lead = world.gear ? world.gear.checkLead(castle, commander, now) : commander ? "No such commander." : null;
  if (typeof lead === "string") return lead;
  castle.useTools(kit);
  const sent: Dict = {};
  for (const unit of Object.keys(army)) {
    if (army[unit] > 0) {
      sent[unit] = army[unit];
      world.castle.troops[unit] -= army[unit];
    }
  }
  const travel = marchTimeTo(world, rules, world.camps.find((c) => c.id === campId)!, now);
  // A lead with id 0 is research alone, without a commander.
  if (lead && lead.id > 0) world.gear!.commander(castle, lead.id)!.away_until = now + 2 * travel;
  world.marches.push({ id: world.nextMarch, camp: campId, army: sent, depart: now, arrive: now + travel,
    back: now + 2 * travel, state: "out", survivors: {}, loot: {}, ...(waves ? { waves } : {}),
    ...(Object.keys(kit).length > 0 ? { tools: kit } : {}), ...(lead ? { lead } : {}) });
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
    defeats: camp?.defeats ?? 0, needed: camp ? rules.forCamp(camp).defeatsNeeded(camp.level) : 0 };
  if (camp === undefined || !isReady(camp, m.arrive)) {
    // The camp was beaten by an earlier army and is still in ashes.
    m.survivors = m.army;
    report.empty = true;
    return report;
  }
  const seed = m.id * 7919 + godotHash(m.camp);
  const result = attackCamp(camp, rules, world.castle.rules, m.army, seed, m.arrive, m.waves, m.tools, m.lead?.fx);
  m.survivors = result.survivors;
  m.loot = result.loot;
  if (result.winner === "a") world.castle.stats.barons += 1;
  const out: Report = { ...report, winner: result.winner, a: result.a, b: result.b, walls: result.walls, courtyard: result.courtyard, ...(result.tools ? { tools: result.tools } : {}), spoils: result.loot, level: result.level,
    leveled: result.leveled, new_level: camp.level, defeats: camp.defeats, needed: rules.forCamp(camp).defeatsNeeded(camp.level) };
  const gear = world.gear;
  if (gear) {
    if (m.lead && m.lead.id > 0) {
      const xp = result.winner === "a" ? gear.xpWinPerLevel * result.level : gear.xpLoss;
      const lead = gear.addXp(world.castle, m.lead.id, xp);
      if (lead) out.lead = lead;
    }
    const item = result.winner === "a" ? gear.rollDrop(result.level + rules.forCamp(camp).dropLevelBonus, seed + DROP_SEED) : null;
    if (item) {
      out.gear = item;
      if (!gear.give(world.castle, item)) out.bag_full = true;
    }
  }
  if (camp.fortress) out.fortress = true;
  if (camp.event !== undefined) {
    out.event = camp.event;
    out.points = result.winner === "a" ? (camp.points ?? 0) * result.level : 0;
    out.needed = 1;
  }
  if (camp.horde !== undefined) {
    // Only battles fought before the horde leaves count, so the ranking is settled when it ends.
    const counts = result.winner === "a" && m.arrive < (camp.until ?? Infinity);
    out.horde = camp.horde;
    out.points = counts ? (camp.points ?? 0) * result.level : 0;
    out.trophies = counts ? (camp.trophies ?? 0) * result.level : 0;
    out.needed = 1;
  }
  return out;
}

function comeHome(world: Army, m: March, at: number): void {
  const castle = world.castle;
  castle.advanceTo(at);
  for (const unit of Object.keys(m.survivors)) castle.troops[unit] = (castle.troops[unit] ?? 0) + m.survivors[unit];
  const cap = castle.storageCapacity();
  for (const r of Object.keys(m.loot)) {
    const have = castle.resources[r] ?? 0;
    castle.resources[r] = Math.max(have, Math.min(cap, have + m.loot[r]));
    castle.stats.looted += m.loot[r];
  }
  m.state = "done";
}
