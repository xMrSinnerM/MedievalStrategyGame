// What the game server does with one player's request, without the
// database: create a new player, or run their world up to now and carry out
// an order. index.ts loads and saves the player and calls in here.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import { autoWaves, checkLayout, checkWaves, siege, survivors, wallFromDefense, wavesArmy, wavesForKeep, type Layout, type Side, type SiegeResult,
  type Wave } from "../../../server/rules/battle.ts";
import { CastleState, type CastleData } from "../../../server/rules/castle_state.ts";
import type { Rules } from "../../../server/rules/load.ts";
import { advanceMarches, sendAttack, type Army, type March, type Report } from "../../../server/rules/marches.ts";
import { godotHash, type Dict } from "../../../server/rules/util.ts";
import type { AllianceRules } from "./alliances.ts";
import { checkShipment, type Aid, type AidRules } from "./aid.ts";
import { lastInvasion, type EventRules } from "../../../server/rules/events.ts";
import { claimReward, eventPoints, invade, rewardTiers } from "./invasion.ts";

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
  /** Robber baron camps your armies have beaten, for the leaderboard. */
  barons_beaten: number;
  /** The start of the last Baron Invasion you played in, and your event points in it. */
  event_key: number;
  event_points: number;
  /** How many of that invasion's reward tiers you have claimed. */
  event_claimed: number;
}

/** The numbers for fights between players, from data/pvp.json. */
export interface PvpRules {
  protection_hours: number;
  protection_until_keep: number;
  loot_share: number;
  spy_cost: Dict;
  /** Leaderboard might: points per building level and per soldier at home. */
  might_per_building_level: number;
  might_per_soldier: number;
  /** Players can't attack castles whose keep is more than this many levels below their own. */
  attack_keep_gap?: number;
}

/** An army one player sent against another (a row of the raids table). */
export interface Raid {
  id: number;
  attacker_name: string;
  defender_name: string;
  army: Dict;
  /** How the army storms the walls; without it, one wave (autoWaves()). */
  waves?: Wave[];
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
  /** Their keep level, if known. */
  level?: number;
  /** In the same alliance as the player giving the order. */
  ally?: boolean;
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
  /** How each wall and the courtyard went (Battle.siege()). */
  walls: SiegeResult["walls"];
  courtyard: SiegeResult["courtyard"];
  spoils: Dict;
  wall: number;
  /** Defender's report: the allies whose soldiers fought beside the garrison. */
  helped_by?: string[];
}

/** Soldiers walking back into the castle, with what they carry. */
export interface Homecoming {
  back: number;
  survivors: Dict;
  loot: Dict;
}

/** What act() needs besides the player: other players and armies coming home. */
export interface Context {
  pvp?: PvpRules;
  target?: Target;
  /** Armies back from attacking players, and defenders back from allies. */
  homecomings?: Homecoming[];
  alliances?: AllianceRules;
  aid?: AidRules;
  /** Timed events, for Baron Invasions; `offset` shifts their clock (local testing). */
  events?: { rules: EventRules; world: World; offset?: number };
}

export interface World {
  home: [number, number];
  /** A camp's starting level: 1 + one per `per_distance` from your castle, up to `max`. */
  camp_levels: { per_distance: number; max: number };
  camps: { id: string; name: string; position: [number, number]; level: number }[];
  /** Where players' castles can stand (scripts/economy/player_spots.gd). */
  spots: [number, number][];
  /** For each spot, where invader camps can stand around it (Baron Invasions). */
  invasion_spots?: [number, number][][];
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
  /** Resources or defenders sent to an ally, for index.ts to store. */
  aid?: Omit<Aid, "id">;
}

export const NAME_RULE = /^[\p{L}\p{N}][\p{L}\p{N} _'-]{1,18}[\p{L}\p{N}]$/u;

export function checkName(name: unknown): string {
  if (typeof name !== "string") return "Choose a name.";
  const trimmed = name.trim();
  if (trimmed.length < 3 || trimmed.length > 20) return "Names are 3 to 20 characters long.";
  if (!NAME_RULE.test(trimmed)) return "Use letters, numbers, spaces, ' _ and - only.";
  return "";
}

/** Spots with room for this many invader camps around them are given out first. */
const ROOMY = 3;

/** A free spot for a new castle, chosen at random; null when the world is full. */
export function pickSpot(world: World, taken: [number, number][], random: () => number = Math.random): [number, number] | null {
  const used = new Set(taken.map(([x, y]) => `${x},${y}`));
  const free = world.spots.filter(([x, y]) => !used.has(`${x},${y}`));
  if (free.length === 0) return null;
  const roomy = free.filter((s) => (world.invasion_spots?.[world.spots.indexOf(s)]?.length ?? 0) >= ROOMY);
  const pool = roomy.length > 0 ? roomy : free;
  return pool[Math.floor(random() * pool.length)];
}

/** The level other players see: your keep's. */
export function castleLevel(castle: CastleData): number {
  return castle.buildings.find((b) => b.type === "keep")?.level ?? 1;
}

/** A castle's might on the leaderboard: its buildings' levels and its garrison. */
export function might(castle: CastleData, pvp: PvpRules): number {
  let levels = 0;
  for (const b of castle.buildings) levels += b.level;
  let soldiers = 0;
  for (const unit of Object.keys(castle.troops)) soldiers += castle.troops[unit];
  return Math.round(levels * pvp.might_per_building_level + soldiers * pvp.might_per_soldier);
}

/** How many of these battle reports are camps beaten. */
export function campsBeaten(reports: Report[]): number {
  return reports.filter((r) => r.winner === "a" && !r.empty).length;
}

/** The leaderboard counts after these battles: camps beaten and event points. */
export function scored(stored: PlayerState, reports: Report[]): Pick<PlayerState, "barons_beaten" | "event_points"> {
  return {
    barons_beaten: (stored.barons_beaten ?? 0) + campsBeaten(reports),
    event_points: (stored.event_points ?? 0) + eventPoints(reports, stored.event_key ?? 0),
  };
}

/** Whether nobody may attack this player now: new, small, and peaceful so far. */
/** Whether a castle at keep `level` is too far below `keep` to be attacked. */
export function tooSmall(keep: number, level: number | undefined, pvp: PvpRules | undefined): boolean {
  return level !== undefined && pvp?.attack_keep_gap !== undefined && keep - level > pvp.attack_keep_gap;
}

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
    barons_beaten: 0,
    event_key: 0,
    event_points: 0,
    event_claimed: 0,
  };
}

/** Brings the player's world up to `now`, then carries out the order (if any). */
export function act(rules: Rules, given: PlayerState, req: Request, now: number, ctx: Context = {}): Outcome {
  const ev = ctx.events;
  const stored = ev ? invade(given, ev.rules, ev.world, now, ev.offset ?? 0) : given;
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
  let aid: Omit<Aid, "id"> | undefined;
  let protectedUntil = stored.protected_until ?? 0;
  let claimed = stored.event_claimed ?? 0;
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
      const waves = req.waves === undefined ? undefined : checkWaves(req.waves, wavesForKeep(castle.keepLevel()), (u) => rules.buildings.hasUnit(u));
      if (typeof waves === "string") {
        error = waves;
        break;
      }
      const sent = waves ? wavesArmy(waves) : isArmy(req.army) ? req.army : null;
      error = sent === null ? "Bad army." : sendAttack(army, rules.barons, String(req.camp), sent, now, waves);
      break;
    }
    case "attack_player": {
      const target = ctx.target;
      const waves = req.waves === undefined ? undefined : checkWaves(req.waves, wavesForKeep(castle.keepLevel()), (u) => rules.buildings.hasUnit(u));
      if (typeof waves === "string") {
        error = waves;
        break;
      }
      const sent = waves ? wavesArmy(waves) : isArmy(req.army) ? req.army : null;
      if (target === undefined) error = "There's no player by that name.";
      else if (target.name === stored.name) error = "That's your own castle.";
      else if (target.ally) error = "You can't attack a member of your own alliance.";
      else if (target.protected) error = "That castle is under beginner protection.";
      else if (tooSmall(castle.keepLevel(), target.level, ctx.pvp)) error = "That castle is too small for you to attack.";
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
        arrive: now + travel, back: now + 2 * travel, state: "out", survivors: {}, loot: {}, ...(waves ? { waves } : {}) };
      // Attacking someone ends your own beginner protection.
      protectedUntil = 0;
      break;
    }
    case "set_layout": {
      error = checkLayout(req.layout);
      if (error === "") castle.layout = { ...(req.layout as Layout) };
      break;
    }
    case "spy": {
      const cost = ctx.pvp?.spy_cost ?? {};
      if (ctx.target === undefined) error = "There's no player by that name.";
      else if (ctx.target.name === stored.name) error = "That's your own castle.";
      else if (ctx.target.ally) error = "No need to spy on your own alliance.";
      else if (!castle.canAfford(cost)) error = "Not enough gold to send a spy.";
      else for (const r of Object.keys(cost)) castle.resources[r] -= cost[r];
      break;
    }
    case "found_alliance": {
      // Only the price is paid here; index.ts creates the alliance itself.
      const a = ctx.alliances;
      if (a === undefined) error = "Unknown order.";
      else if (castle.keepLevel() < a.found_keep) error = `Founding an alliance needs keep level ${a.found_keep}.`;
      else if (!castle.canAfford(a.found_cost)) error = "Not enough gold to found an alliance.";
      else for (const r of Object.keys(a.found_cost)) castle.resources[r] -= a.found_cost[r];
      break;
    }
    case "send_resources":
    case "send_defenders": {
      const target = ctx.target;
      const troops = req.action === "send_defenders";
      if (ctx.aid === undefined) error = "Unknown order.";
      else if (target === undefined) error = "There's no player by that name.";
      else if (target.name === stored.name) error = "That's your own castle.";
      else if (!target.ally) error = "You can only help members of your own alliance.";
      else if (troops) error = isArmy(req.army) ? checkArmy(castle, req.army) : "Bad army.";
      else error = checkShipment(castle, ctx.aid, req.resources);
      if (error !== "" || target === undefined || ctx.aid === undefined) break;
      const sent: Dict = {};
      const pool = troops ? castle.troops : castle.resources;
      const asked: Dict = troops ? req.army : req.resources;
      for (const k of Object.keys(asked)) {
        if (asked[k] > 0) {
          sent[k] = asked[k];
          pool[k] -= asked[k];
        }
      }
      const from: [number, number] = [stored.home_x, stored.home_y];
      const travel = rules.barons.marchTime(Math.hypot(target.home[0] - from[0], target.home[1] - from[1]));
      const leave = troops ? now + travel + ctx.aid.station_hours * 3600 : now + travel;
      aid = { kind: troops ? "troops" : "resources", sender_name: stored.name, receiver_name: target.name,
        resources: troops ? {} : sent, army: troops ? sent : {}, from, to: target.home, depart: now, arrive: now + travel,
        leave, back: troops ? leave + travel : now + travel };
      break;
    }
    case "claim_reward": {
      // Points count for the invasion on now, or the last one until the next begins.
      const last = ev ? lastInvasion(ev.rules, now + (ev.offset ?? 0)) : undefined;
      const current = last !== undefined && stored.event_key === last.start - (ev?.offset ?? 0);
      error = claimReward(castle, current ? stored.event_points ?? 0 : 0, current ? claimed : 0,
        ev ? rewardTiers(ev.rules) : [], req.tier);
      if (error === "") claimed = (current ? claimed : 0) + 1;
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
      event_claimed: claimed,
      ...scored(stored, reports),
    },
    reports,
    error,
    result,
    raid,
    aid,
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

/** Survivors of an attack on a player, or defenders back from an ally, walk back in with what they carry. */
function comeHomeFromRaid(castle: CastleState, raid: Homecoming): void {
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
  /** What is left of each group of allied defenders, in the order given. */
  helpers: Dict[];
}

/**
 * An army reaches another player's castle: the defender's world runs up to
 * that moment, the army fights their garrison and any allied defenders
 * (`helpers`) behind their wall, and if it wins it takes up to `loot_share`
 * of each resource, as much as it can carry. Losses fall on the garrison
 * and the defenders in proportion to their numbers.
 */
export function fightRaid(rules: Rules, pvp: PvpRules, stored: PlayerState, raid: Raid, helpers: Dict[] = []): RaidOutcome {
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
  const groups: Dict[] = [castle.troops, ...helpers.map((h) => ({ ...h }))];
  const defenders: Dict = {};
  for (const g of groups) for (const unit of Object.keys(g)) defenders[unit] = (defenders[unit] ?? 0) + g[unit];
  const result = siege(rules.buildings, raid.waves ?? autoWaves(raid.army), defenders, castle.layout, raid.id * 7919 + godotHash(raid.defender_name),
    wall);
  for (const unit of Object.keys(result.b)) shareLosses(groups, unit, result.b[unit].lost);
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
    walls: result.walls, courtyard: result.courtyard, spoils: loot, wall,
  });
  return {
    defender: {
      ...stored,
      castle: castle.toDict(),
      camps: world.camps,
      marches: world.marches,
      next_march: world.nextMarch,
      ...scored(stored, campReports),
    },
    campReports,
    attackerReport: report("attacker", raid.defender_name),
    defenderReport: report("defender", raid.attacker_name),
    survivors: back,
    loot,
    helpers: groups.slice(1).map((g) => {
      const left: Dict = {};
      for (const unit of Object.keys(g)) if (g[unit] > 0) left[unit] = g[unit];
      return left;
    }),
  };
}

/** Takes `lost` soldiers of one unit from the groups, in proportion to how many each has. */
function shareLosses(groups: Dict[], unit: string, lost: number): void {
  const total = groups.reduce((n, g) => n + (g[unit] ?? 0), 0);
  if (total <= 0 || lost <= 0) return;
  const cut = groups.map((g) => Math.floor(lost * (g[unit] ?? 0) / total));
  let left = lost - cut.reduce((a, b) => a + b, 0);
  for (let i = 0; i < groups.length && left > 0; i++) {
    const extra = Math.min((groups[i][unit] ?? 0) - cut[i], left);
    cut[i] += extra;
    left -= extra;
  }
  groups.forEach((g, i) => {
    if (unit in g) g[unit] = Math.max(0, g[unit] - cut[i]);
  });
}

/** What a spy sees: the soldiers at home (with any allied defenders) and the wall, as of now. */
export function spyReport(rules: Rules, pvp: PvpRules, stored: PlayerState, now: number, helpers: Dict[] = []) {
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
  for (const group of [world.castle.troops, ...helpers]) {
    for (const unit of Object.keys(group)) if (group[unit] > 0) troops[unit] = (troops[unit] ?? 0) + group[unit];
  }
  return {
    name: stored.name, at: now, level: castleLevel(stored.castle), troops,
    wall: wallFromDefense(world.castle.defense()), layout: world.castle.layout, protected: isProtected(stored, pvp, now),
  };
}

function isCell(cell: unknown): cell is [number, number] {
  return Array.isArray(cell) && cell.length === 2 && cell.every((v) => Number.isInteger(v));
}

function isArmy(army: unknown): army is Record<string, number> {
  return army !== null && typeof army === "object" && !Array.isArray(army) &&
    Object.values(army as object).every((v) => typeof v === "number");
}
