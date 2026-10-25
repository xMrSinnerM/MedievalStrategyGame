// The Ember Horde (a timed event, see data/events.json): while it runs,
// every castle gets the horde's camps nearby, which rise a level with every
// win and give horde points (for the ranking) and war trophies (for the
// Trophy Market). Once the horde has gone, every player with points claims
// one ranked prize. Like the invader camps, horde camps are ordinary camps
// in the player's camp list, with `horde` set; this file adds and removes
// them, keeps the score and runs the market and the prizes.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import type { CastleState } from "../../../server/rules/castle_state.ts";
import { activeEvents, lastHorde, type EventRules, type EventTime, type HordePrize, type HordeRules, type MarketItem }
  from "../../../server/rules/events.ts";
import type { GearRules } from "../../../server/rules/gear.ts";
import type { Report } from "../../../server/rules/marches.ts";
import type { Dict } from "../../../server/rules/util.ts";
import type { PlayerState, World } from "./game.ts";

/** What a player has of the horde's last run: war trophies to spend, what they bought, and whether they took their prize. */
export interface HordeState {
  trophies: number;
  /** Market item id -> how many times bought. */
  bought: Dict;
  ranked: boolean;
}

export function emptyHorde(): HordeState {
  return { trophies: 0, bought: {}, ranked: false };
}

/** Which of the horde's camps stand around a castle with room for `room` of them: all, or else the Warlord's first. */
export function campsFor(rules: HordeRules, room: number): HordeRules["camps"] {
  if (room >= rules.camps.length) return rules.camps;
  const warlords = rules.camps.filter((c) => c.warlord);
  const others = rules.camps.filter((c) => !c.warlord);
  return [...warlords, ...others].slice(0, Math.max(0, room));
}

/**
 * The player's camps and horde score as of `t`: when the horde has arrived
 * since they last played, its camps appear (on the spots world.json lists
 * around their castle) and their points, trophies and purchases start again.
 * Horde camps of a run that is over leave once no army is marching to or
 * from them. `offset` runs the event calendar that many seconds ahead
 * (local testing); runs are still keyed by their start on the real clock.
 */
export function hordeArrives(stored: PlayerState, events: EventRules, world: World, t: number, offset = 0): PlayerState {
  const on = activeEvents(events, t + offset).find((e) => e.horde !== undefined);
  const start = on === undefined ? undefined : on.start - offset;
  const busy = new Set(stored.marches.map((m) => m.camp));
  const camps = stored.camps.filter((c) => c.horde === undefined || c.horde === start || busy.has(c.id));
  const key = stored.horde_key ?? 0;
  if (on?.horde !== undefined && start !== undefined && key !== start) {
    const rules = on.horde;
    const spot = (world.spots ?? []).findIndex(([x, y]) => x === stored.home_x && y === stored.home_y);
    const places = spot < 0 ? [] : world.invasion_spots?.[spot] ?? [];
    const keep = stored.castle.buildings.find((b) => b.type === "keep")?.level ?? 1;
    const first = 1 + rules.level_per_keep * (keep - 1);
    campsFor(rules, places.length).forEach((c, i) => {
      camps.push({
        id: `horde_${start}_${i}`,
        name: c.name,
        position: [places[i][0], places[i][1]],
        level: first + c.level,
        defeats: 0,
        rebuilt_at: 0,
        horde: start,
        points: c.points,
        trophies: c.trophies,
        rebuild: rules.rebuild,
        until: on.end - offset,
      } satisfies CampData);
    });
    return { ...stored, camps, horde_key: start, horde_points: 0, horde: emptyHorde() };
  }
  if (camps.length === stored.camps.length) return stored;
  return { ...stored, camps };
}

/** The horde's run the player's score belongs to, on the real clock, or undefined when that run is no longer the last one. */
export function playerRun(events: EventRules, key: number, t: number, offset = 0): EventTime | undefined {
  const last = lastHorde(events, t + offset);
  if (last === undefined || last.start - offset !== key || key === 0) return undefined;
  return { ...last, start: last.start - offset, end: last.end - offset };
}

/** Horde points and war trophies won in these battle reports for the run starting at `key` (battles fought after
 * the run's end win none, see marches.ts). */
export function hordeScore(reports: Report[], key: number): { points: number; trophies: number } {
  let points = 0;
  let trophies = 0;
  for (const r of reports) {
    if (r.horde === undefined || r.horde !== key) continue;
    points += r.points ?? 0;
    trophies += r.trophies ?? 0;
  }
  return { points, trophies };
}

/** Why the castle's storage can't take all of these resources ("" if it can). */
function checkRoom(castle: CastleState, resources: Dict): string {
  const cap = castle.storageCapacity();
  for (const [r, n] of Object.entries(resources)) {
    if (r in castle.resources && castle.resources[r] + n > cap) return "Make room in your storage first: it can't hold all of that.";
  }
  return "";
}

/** Puts resources (up to the storage), soldiers and siege tools in the castle. */
function give(castle: CastleState, what: { resources?: Dict; troops?: Dict; tools?: Dict }): void {
  const cap = castle.storageCapacity();
  for (const [r, n] of Object.entries(what.resources ?? {})) {
    if (!(r in castle.resources)) continue;
    const have = castle.resources[r];
    castle.resources[r] = Math.max(have, Math.min(cap, have + n));
  }
  for (const [unit, n] of Object.entries(what.troops ?? {})) {
    if (castle.rules.hasUnit(unit)) castle.troops[unit] = (castle.troops[unit] ?? 0) + n;
  }
  for (const [tool, n] of Object.entries(what.tools ?? {})) {
    if (castle.rules.hasTool(tool)) castle.tools[tool] = (castle.tools[tool] ?? 0) + n;
  }
}

/**
 * Buys market item `id` for war trophies, while the player's run is the
 * last one (during the horde and until the next arrives). Resources must
 * fit in the storage; gear must fit in the bag. Changes `horde` and the
 * castle; returns "" or why not.
 */
export function buy(castle: CastleState, gear: GearRules, horde: HordeState, run: EventTime | undefined, id: unknown): string {
  const market: MarketItem[] = run?.horde?.market ?? [];
  if (run === undefined) return "The Trophy Market opens when the Ember Horde arrives.";
  const item = market.find((m) => m.id === id);
  if (item === undefined) return "The market doesn't sell that.";
  if ((horde.bought[item.id] ?? 0) >= item.stock) return "That's sold out until the next horde.";
  if (horde.trophies < item.cost) return `That costs ${item.cost} war trophies.`;
  const room = checkRoom(castle, item.resources ?? {});
  if (room !== "") return room;
  if (item.gear) {
    if (!gear.give(castle, { id: 0, ...structuredClone(item.gear) })) return "Your gear bag is full.";
  }
  give(castle, item);
  horde.trophies -= item.cost;
  horde.bought[item.id] = (horde.bought[item.id] ?? 0) + 1;
  return "";
}

/** The prize for this rank (1 is best): the first one whose `up_to` the rank reaches; undefined without one. */
export function prizeFor(prizes: HordePrize[], rank: number): HordePrize | undefined {
  if (rank < 1) return undefined;
  return prizes.find((p) => p.up_to <= 0 || rank <= p.up_to);
}

/**
 * Gives the player their ranked prize once the horde has gone: `rank` is
 * their place among the players of that run (index.ts counts it). Resources
 * fill the storage (what doesn't fit is lost), soldiers join the garrison
 * and trophies go to the market. Returns "" or why not.
 */
export function claimPrize(castle: CastleState, horde: HordeState, points: number, run: EventTime | undefined, rank: number,
  now: number): string {
  if (run === undefined || points <= 0) return "Beat horde camps for points to earn a prize.";
  if (now < run.end) return "The prizes are given once the horde has gone.";
  if (horde.ranked) return "You already have your prize.";
  const prize = prizeFor(run.horde?.prizes ?? [], rank);
  if (prize === undefined) return "There's no prize for that rank.";
  give(castle, prize);
  horde.trophies += prize.trophies ?? 0;
  horde.ranked = true;
  return "";
}
