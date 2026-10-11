// What the game server does with one player's request, without the
// database: create a new player, or run their world up to now and carry out
// an order. index.ts loads and saves the player and calls in here.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import { fight, survivors, wallFromDefense, type Side } from "../../../server/rules/battle.ts";
import { CastleState, type CastleData } from "../../../server/rules/castle_state.ts";
import type { Rules } from "../../../server/rules/load.ts";
import { advanceMarches, sendAttack, type Army, type March, type Report } from "../../../server/rules/marches.ts";
import { godotHash, type Dict } from "../../../server/rules/util.ts";

/** A player as stored in the players table (the game columns). */
export interface PlayerState {
  name: string;
  home_x: number;
  home_y: number;
  castle: CastleData;
  camps: CampData[];
  marches: March[];
  next_march: number;
  /** Unix time until which nobody can attack you (see isProtected). */
  protected_until: number;
}

/** The numbers for fights between players, from data/pvp.json. */
export interface PvpRules {
  protection_hours: number;
  protection_until_keep: number;
  loot_share: number;
  spy_cost: Dict;
}

/** An army one player sent against another (a row of the raids table). */
export interface Raid {
  id: number;
  attacker_name: string;
  defender_name: string;
  army: Dict;
  from: [number, number];
  to: [number, number];
  depart: number;
  arrive: number;
  back: number;
  state: "out" | "fighting" | "home" | "done";
  survivors: Dict;
  loot: Dict;
}

/** Another player an order is aimed at, as index.ts found them. */
export interface Target {
  name: string;
  home: [number, number];
  protected: boolean;
}

/** A battle between players, as each side's report shows it. */
export interface RaidReport {
  kind: "raid";
  role: "attacker" | "defender";
  raid: number;
  /** The other player. */
  name: string;
  at: number;
  winner: "a" | "b";
  a: Side;
  b: Side;
  spoils: Dict;
  wall: number;
}

/** What act() needs besides the player: other players and armies coming home. */
export interface Context {
  pvp?: PvpRules;
  target?: Target;
  homecomings?: Raid[];
}

export interface World {
  home: [number, number];
  /** A camp's starting level: 1 + one per `per_distance` from your castle, up to `max`. */
  camp_levels: { per_distance: number; max: number };
  camps: { id: string; name: string; position: [number, number]; level: number }[];
  /** Where players' castles can stand (scripts/economy/player_spots.gd). */
  spots: [number, number][];
}

/** What other players see of you on the map. */
export interface PublicPlayer {
  name: string;
  home_x: number;
  home_y: number;
  level: number;
}

// deno-lint-ignore no-explicit-any
export type Request = Record<string, any>;

export interface Outcome {
  state: PlayerState;
  reports: Report[];
  error: string;
  /** Extra answer for the order, such as the id of a new building. */
  result?: unknown;
  /** An army sent against another player, for index.ts to store. */
  raid?: Omit<Raid, "id">;
}

export const NAME_RULE = /^[\p{L}\p{N}][\p{L}\p{N} _'-]{1,18}[\p{L}\p{N}]$/u;

export function checkName(name: unknown): string {
  if (typeof name !== "string") return "Choose a name.";
  const trimmed = name.trim();
  if (trimmed.length < 3 || trimmed.length > 20) return "Names are 3 to 20 characters long.";
  if (!NAME_RULE.test(trimmed)) return "Use letters, numbers, spaces, ' _ and - only.";
  return "";
}

/** A free spot for a new castle, chosen at random; null when the world is full. */
export function pickSpot(world: World, taken: [number, number][], random: () => number = Math.random): [number, number] | null {
  const used = new Set(taken.map(([x, y]) => `${x},${y}`));
  const free = world.spots.filter(([x, y]) => !used.has(`${x},${y}`));
  if (free.length === 0) return null;
  return free[Math.floor(random() * free.length)];
}

/** The level other players see: your keep's. */
export function castleLevel(castle: CastleData): number {
  return castle.buildings.find((b) => b.type === "keep")?.level ?? 1;
}

/** Whether nobody may attack this player now: new, small, and peaceful so far. */
export function isProtected(state: Pick<PlayerState, "protected_until" | "castle">, pvp: PvpRules, now: number): boolean {
  return state.protected_until > now && castleLevel(state.castle) < pvp.protection_until_keep;
}

export function newPlayer(rules: Rules, world: World, name: string, now: number, spot: [number, number] = world.home,
  pvp?: PvpRules): PlayerState {
  const castle = CastleState.createNew(rules.buildings, "player_castle", `${name.trim()}'s Castle`, "player", now);
  const { per_distance, max } = world.camp_levels;
  const startLevel = (p: [number, number]) =>
    Math.min(max, Math.max(1, 1 + Math.floor(Math.hypot(p[0] - spot[0], p[1] - spot[1]) / per_distance)));
  return {
    name: name.trim(),
    home_x: spot[0],
    home_y: spot[1],
    castle: castle.toDict(),
    camps: world.camps.map((c) => ({ id: c.id, name: c.name, position: [c.position[0], c.position[1]], level: startLevel(c.position), defeats: 0, rebuilt_at: 0 })),
    marches: [],
    next_march: 1,
    protected_until: pvp ? now + pvp.protection_hours * 3600 : 0,
  };
}

/** Brings the player's world up to `now`, then carries out the order (if any). */
export function act(rules: Rules, stored: PlayerState, req: Request, now: number, ctx: Context = {}): Outcome {
  const army: Army = {
    castle: CastleState.fromDict(rules.buildings, stored.castle),
    camps: structuredClone(stored.camps),
    marches: structuredClone(stored.marches),
    nextMarch: stored.next_march,
    home: [stored.home_x, stored.home_y],
  };
  const reports = advanceMarches(army, rules.barons, now);
  const castle = army.castle;
  for (const raid of [...(ctx.homecomings ?? [])].sort((x, y) => x.back - y.back)) comeHomeFromRaid(castle, raid);
  castle.advanceTo(now);
  let error = "";
  let result: unknown = undefined;
  let raid: Omit<Raid, "id"> | undefined;
  let protectedUntil = stored.protected_until ?? 0;
  switch (req.action) {
    case "state":
      break;
    case "place": {
      if (!isCell(req.cell)) {
        error = "Bad cell.";
        break;
      }
      error = castle.checkPlace(String(req.type), req.cell);
      if (error === "") result = castle.place(String(req.type), req.cell, now);
      break;
    }
    case "upgrade":
      error = castle.checkUpgrade(Number(req.id));
      if (error === "") castle.upgrade(Number(req.id), now);
      break;
    case "cancel":
      if (!castle.cancel(Number(req.id), now)) error = "Nothing is being built there.";
      break;
    case "move":
      if (!isCell(req.cell) || !castle.move(Number(req.id), req.cell)) error = "There's no room there";
      break;
    case "recruit":
      error = castle.checkRecruit(String(req.unit), Number(req.amount));
      if (error === "") castle.recruit(String(req.unit), Number(req.amount), now);
      break;
    case "cancel_training":
      if (!castle.cancelTraining(Number(req.index), now)) error = "No such batch.";
      break;
    case "attack": {
      const sent = isArmy(req.army) ? req.army : null;
      error = sent === null ? "Bad army." : sendAttack(army, rules.barons, String(req.camp), sent, now);
      break;
    }
    case "attack_player": {
      const target = ctx.target;
      const sent = isArmy(req.army) ? req.army : null;
      if (target === undefined) error = "There's no player by that name.";
      else if (target.name === stored.name) error = "That's your own castle.";
      else if (target.protected) error = "That castle is under beginner protection.";
      else if (sent === null) error = "Bad army.";
      else error = checkArmy(castle, sent);
      if (error !== "" || target === undefined || sent === null) break;
      const army: Dict = {};
      for (const unit of Object.keys(sent)) {
        if (sent[unit] > 0) {
          army[unit] = sent[unit];
          castle.troops[unit] -= sent[unit];
        }
      }
      const from: [number, number] = [stored.home_x, stored.home_y];
      const travel = rules.barons.marchTime(Math.hypot(target.home[0] - from[0], target.home[1] - from[1]));
      raid = { attacker_name: stored.name, defender_name: target.name, army, from, to: target.home, depart: now,
        arrive: now + travel, back: now + 2 * travel, state: "out", survivors: {}, loot: {} };
      // Attacking someone ends your own beginner protection.
      protectedUntil = 0;
      break;
    }
    case "spy": {
      const cost = ctx.pvp?.spy_cost ?? {};
      if (ctx.target === undefined) error = "There's no player by that name.";
      else if (ctx.target.name === stored.name) error = "That's your own castle.";
      else if (!castle.canAfford(cost)) error = "Not enough gold to send a spy.";
      else for (const r of Object.keys(cost)) castle.resources[r] -= cost[r];
      break;
    }
    default:
      error = "Unknown order.";
  }
  return {
    state: {
      ...stored,
      castle: castle.toDict(),
      camps: army.camps,
      marches: army.marches,
      next_march: army.nextMarch,
      protected_until: protectedUntil,
    },
    reports,
    error,
    result,
    raid,
  };
}

/** Why this army can't leave the garrison ("" if it can). */
function checkArmy(castle: CastleState, army: Dict): string {
  let total = 0;
  for (const unit of Object.keys(army)) {
    const n = army[unit];
    if (!castle.rules.hasUnit(unit)) return "Unknown unit.";
    if (!Number.isInteger(n) || n < 0 || n > (castle.troops[unit] ?? 0)) return "Your garrison doesn't have that many soldiers.";
    total += n;
  }
  return total > 0 ? "" : "Choose some soldiers to send.";
}

/** Survivors of an attack on a player walk back in with what they carry. */
function comeHomeFromRaid(castle: CastleState, raid: Raid): void {
  castle.advanceTo(raid.back);
  for (const unit of Object.keys(raid.survivors)) {
    if (castle.rules.hasUnit(unit)) castle.troops[unit] = (castle.troops[unit] ?? 0) + raid.survivors[unit];
  }
  const cap = castle.storageCapacity();
  for (const r of Object.keys(raid.loot)) {
    if (!(r in castle.resources)) continue;
    const have = castle.resources[r];
    castle.resources[r] = Math.max(have, Math.min(cap, have + raid.loot[r]));
  }
}

export interface RaidOutcome {
  /** The defender, run up to the battle and after it. */
  defender: PlayerState;
  /** Battles the defender's own armies fought on the way (robber barons). */
  campReports: Report[];
  attackerReport: RaidReport;
  defenderReport: RaidReport;
  survivors: Dict;
  loot: Dict;
}

/**
 * An army reaches another player's castle: the defender's world runs up to
 * that moment, the army fights their garrison behind their wall, and if it
 * wins it takes up to `loot_share` of each resource, as much as it can carry.
 */
export function fightRaid(rules: Rules, pvp: PvpRules, stored: PlayerState, raid: Raid): RaidOutcome {
  const world: Army = {
    castle: CastleState.fromDict(rules.buildings, stored.castle),
    camps: structuredClone(stored.camps),
    marches: structuredClone(stored.marches),
    nextMarch: stored.next_march,
    home: [stored.home_x, stored.home_y],
  };
  const campReports = advanceMarches(world, rules.barons, raid.arrive);
  const castle = world.castle;
  castle.advanceTo(raid.arrive);
  const wall = wallFromDefense(castle.defense());
  const result = fight(rules.buildings, raid.army, castle.troops, raid.id * 7919 + godotHash(raid.defender_name), wall);
  for (const unit of Object.keys(result.b)) castle.troops[unit] = Math.max(0, (castle.troops[unit] ?? 0) - result.b[unit].lost);
  const back = survivors(result.a);
  const loot: Dict = {};
  if (result.winner === "a") {
    let all = 0;
    for (const r of Object.keys(castle.resources)) {
      loot[r] = Math.floor(castle.resources[r] * pvp.loot_share);
      all += loot[r];
    }
    const capacity = rules.barons.carry(back);
    const share = all <= capacity ? 1 : capacity / all;
    for (const r of Object.keys(loot)) {
      loot[r] = Math.floor(loot[r] * share);
      castle.resources[r] -= loot[r];
    }
  }
  const report = (role: "attacker" | "defender", name: string): RaidReport => ({
    kind: "raid", role, raid: raid.id, name, at: raid.arrive, winner: result.winner, a: result.a, b: result.b,
    spoils: loot, wall,
  });
  return {
    defender: {
      ...stored,
      castle: castle.toDict(),
      camps: world.camps,
      marches: world.marches,
      next_march: world.nextMarch,
    },
    campReports,
    attackerReport: report("attacker", raid.defender_name),
    defenderReport: report("defender", raid.attacker_name),
    survivors: back,
    loot,
  };
}

/** What a spy sees: the soldiers at home and the wall, as of now. */
export function spyReport(rules: Rules, pvp: PvpRules, stored: PlayerState, now: number) {
  const world: Army = {
    castle: CastleState.fromDict(rules.buildings, stored.castle),
    camps: structuredClone(stored.camps),
    marches: structuredClone(stored.marches),
    nextMarch: stored.next_march,
    home: [stored.home_x, stored.home_y],
  };
  advanceMarches(world, rules.barons, now);
  world.castle.advanceTo(now);
  const troops: Dict = {};
  for (const unit of Object.keys(world.castle.troops)) if (world.castle.troops[unit] > 0) troops[unit] = world.castle.troops[unit];
  return {
    name: stored.name, at: now, level: castleLevel(stored.castle), troops,
    wall: wallFromDefense(world.castle.defense()), protected: isProtected(stored, pvp, now),
  };
}

function isCell(cell: unknown): cell is [number, number] {
  return Array.isArray(cell) && cell.length === 2 && cell.every((v) => Number.isInteger(v));
}

function isArmy(army: unknown): army is Record<string, number> {
  return army !== null && typeof army === "object" && !Array.isArray(army) &&
    Object.values(army as object).every((v) => typeof v === "number");
}
