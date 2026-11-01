// Alliance wars (data/wars.json): alliances fight over the capitals in
// weekly seasons. War points are rows of a log, one for every hour an
// alliance holds a capital, every capital it takes and every attack it holds
// one against; a season's standings add them up. Once the season is over,
// every member of an alliance with points claims one prize by its place.
// This file has the rules without the database: index.ts (and the local
// server) store the points and call in here.

import type { Side } from "../../../server/rules/battle.ts";
import type { CastleState } from "../../../server/rules/castle_state.ts";
import { addMarks } from "../../../server/rules/gear.ts";
import type { Dict } from "../../../server/rules/util.ts";
import type { VillageInfo } from "../../../server/rules/villages.ts";

/** A prize for every member of the alliances placed `up_to` or better (0: any place). */
export interface WarPrize {
  up_to: number;
  resources?: Dict;
  troops?: Dict;
  /** Marks, the trade coin (server/rules/gear.ts). */
  marks?: number;
}

export interface WarRules {
  /** A season starts on `day` (1 = Monday ... 7 = Sunday) at `hour` UTC and lasts `days` days. */
  day: number;
  hour: number;
  days: number;
  /** War points per hour for each level of a capital held. */
  hold_per_hour: number;
  /** War points per level of a capital for taking it (once per capital, alliance and season). */
  capture: number;
  /** War points for each attacker who fell at a capital its holder kept, at most `defence_max` per level a battle. */
  defence_per_soldier: number;
  defence_max: number;
  /** How many alliances the standings list. */
  shown: number;
  /** Best place first. */
  prizes: WarPrize[];
}

/** A season: from `start` to `end` (Unix seconds). */
export interface Season {
  start: number;
  end: number;
}

/** The alliance points go to. */
export interface WarAlliance {
  id: number;
  name: string;
  tag: string;
}

/** War points won: a row of the war_points table. */
export interface WarEntry {
  season: number;
  alliance_id: number;
  name: string;
  tag: string;
  capital: string;
  kind: "hold" | "capture" | "defence";
  points: number;
  at: number;
}

/** An alliance's place in a season. */
export interface Standing {
  alliance_id: number;
  name: string;
  tag: string;
  points: number;
  captures: number;
  defences: number;
  /** 1 is best; alliances with the same points share a place. */
  rank: number;
}

/** A capital as the war screen shows it. */
export interface CapitalHold {
  id: string;
  name: string;
  level: number;
  /** Its holder ("" for the town guard) and their alliance (null outside one). */
  owner: string;
  alliance_id: number | null;
  tag: string;
}

/** What the war needs to know about a player: their alliance, when they joined it, and the season whose prize they took. */
export interface WarMember {
  alliance_id: number | null;
  joined: number;
  war_claimed: number;
}

const DAY = 86400;
const HOUR = 3600;
// 1970-01-01 was a Thursday, so Monday 00:00 UTC of that week was 3 days earlier.
const MONDAY = -3 * DAY;

/** The season on at `t`. */
export function seasonAt(rules: WarRules, t: number): Season {
  const length = rules.days * DAY;
  const first = MONDAY + (rules.day - 1) * DAY + rules.hour * HOUR;
  const start = first + Math.floor((t - first) / length) * length;
  return { start, end: start + length };
}

/** The season before the one on at `t`: the one whose prizes can be claimed. */
export function lastSeason(rules: WarRules, t: number): Season {
  const now = seasonAt(rules, t);
  return { start: now.start - rules.days * DAY, end: now.start };
}

/** The start of the hour `t` is in: hold points are counted up to there. */
export function hourStart(t: number): number {
  return Math.floor(t / HOUR) * HOUR;
}

/**
 * The time a capital's holder has held it since its points were last
 * counted: from `scoredAt` (or when they took it, if later) to the start of
 * this hour; null when there is nothing to count yet.
 */
export function holdDue(scoredAt: number, takenAt: number, t: number): { from: number; to: number } | null {
  const from = Math.max(scoredAt, takenAt);
  const to = hourStart(t);
  return to > from ? { from, to } : null;
}

/** Hold points for an alliance that held this capital from `from` to `to`, split between the seasons the time falls in. */
export function holdEntries(rules: WarRules, info: VillageInfo, alliance: WarAlliance, from: number, to: number): WarEntry[] {
  const out: WarEntry[] = [];
  let t = from;
  while (t < to) {
    const season = seasonAt(rules, t);
    const until = Math.min(to, season.end);
    const points = rules.hold_per_hour * info.level * (until - t) / HOUR;
    if (points > 0) {
      out.push({ season: season.start, alliance_id: alliance.id, name: alliance.name, tag: alliance.tag, capital: info.id,
        kind: "hold", points, at: until });
    }
    t = until;
  }
  return out;
}

/** Points for taking this capital at `at`, unless the alliance already took it this season (`already`). */
export function captureEntry(rules: WarRules, info: VillageInfo, alliance: WarAlliance, at: number, already: boolean): WarEntry | null {
  if (already) return null;
  return { season: seasonAt(rules, at).start, alliance_id: alliance.id, name: alliance.name, tag: alliance.tag, capital: info.id,
    kind: "capture", points: rules.capture * info.level, at };
}

/** Points for holding this capital against an attack: per attacker who fell (side a of the battle), up to the cap. */
export function defenceEntry(rules: WarRules, info: VillageInfo, alliance: WarAlliance, at: number, attackers: Side): WarEntry | null {
  let fell = 0;
  for (const unit of Object.keys(attackers)) fell += attackers[unit].lost;
  const points = Math.min(rules.defence_max * info.level, Math.floor(fell * rules.defence_per_soldier));
  if (points <= 0) return null;
  return { season: seasonAt(rules, at).start, alliance_id: alliance.id, name: alliance.name, tag: alliance.tag, capital: info.id,
    kind: "defence", points, at };
}

/** Puts alliances in order, most points first, and gives each its place (the same points share one). */
export function ranked(rows: Omit<Standing, "rank">[]): Standing[] {
  const sorted = [...rows].sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
  return sorted.map((r) => ({ ...r, rank: 1 + sorted.filter((o) => o.points > r.points).length }));
}

/** A season's standings from its war points. */
export function standings(entries: WarEntry[], season: number): Standing[] {
  const by = new Map<number, Omit<Standing, "rank">>();
  for (const e of entries) {
    if (e.season !== season) continue;
    const s = by.get(e.alliance_id) ?? { alliance_id: e.alliance_id, name: e.name, tag: e.tag, points: 0, captures: 0, defences: 0 };
    s.name = e.name;
    s.tag = e.tag;
    s.points += e.points;
    if (e.kind === "capture") s.captures++;
    if (e.kind === "defence") s.defences++;
    by.set(e.alliance_id, s);
  }
  return ranked([...by.values()].filter((s) => s.points > 0));
}

/** The prize for this place (1 is best): the first whose `up_to` the place reaches; undefined without one. */
export function prizeFor(prizes: WarPrize[], rank: number): WarPrize | undefined {
  if (rank < 1) return undefined;
  return prizes.find((p) => p.up_to <= 0 || rank <= p.up_to);
}

/**
 * The prize this player can claim for the last season, from their
 * alliance's place in it (`standing`, undefined without points), or why not.
 */
export function checkClaim(rules: WarRules, me: WarMember, standing: Standing | undefined, t: number): WarPrize | string {
  const last = lastSeason(rules, t);
  if (me.alliance_id === null) return "Join an alliance to fight in the alliance wars.";
  if (me.war_claimed === last.start) return "You already have your prize for the last season.";
  if (standing === undefined) return "Your alliance won no war points last season.";
  if (me.joined >= last.end) return "You joined your alliance after the last season ended.";
  return prizeFor(rules.prizes, standing.rank) ?? "There's no prize for that place.";
}

/** Puts a prize in the castle: resources up to the storage (what doesn't fit is lost), soldiers in the garrison. */
export function givePrize(castle: CastleState, prize: WarPrize): void {
  if (prize.marks) addMarks(castle, prize.marks);
  const cap = castle.storageCapacity();
  for (const [r, n] of Object.entries(prize.resources ?? {})) {
    if (!(r in castle.resources)) continue;
    const have = castle.resources[r];
    castle.resources[r] = Math.max(have, Math.min(cap, have + n));
  }
  for (const [unit, n] of Object.entries(prize.troops ?? {})) {
    if (castle.rules.hasUnit(unit)) castle.troops[unit] = (castle.troops[unit] ?? 0) + n;
  }
}

function shown(s: Standing) {
  return { ...s, points: Math.floor(s.points) };
}

/**
 * What the war screen shows: this season with its standings and who holds
 * each capital (and the points it earns them an hour), the last season's
 * standings, and the player's alliance in both with the prize they can claim.
 */
export function warBoard(rules: WarRules, t: number, current: Standing[], last: Standing[], capitals: CapitalHold[],
  me: WarMember | null) {
  const season = seasonAt(rules, t);
  const before = lastSeason(rules, t);
  const held = new Map<number, number>();
  for (const c of capitals) if (c.alliance_id !== null) held.set(c.alliance_id, (held.get(c.alliance_id) ?? 0) + 1);
  const mineNow = me?.alliance_id != null ? current.find((s) => s.alliance_id === me.alliance_id) : undefined;
  const mineLast = me?.alliance_id != null ? last.find((s) => s.alliance_id === me.alliance_id) : undefined;
  const claim = me === null ? "Found your castle first." : checkClaim(rules, me, mineLast, t);
  return {
    season: { ...season, alliances: current.slice(0, rules.shown).map((s) => ({ ...shown(s), capitals: held.get(s.alliance_id) ?? 0 })) },
    last: { ...before, alliances: last.slice(0, rules.shown).map(shown) },
    capitals: capitals.map((c) => ({ ...c, per_hour: c.alliance_id === null ? 0 : rules.hold_per_hour * c.level })),
    mine: me?.alliance_id != null ? {
      alliance_id: me.alliance_id,
      now: mineNow ? shown(mineNow) : null,
      last: mineLast ? shown(mineLast) : null,
      capitals: held.get(me.alliance_id) ?? 0,
    } : null,
    prize: {
      prize: typeof claim === "string" ? (mineLast ? prizeFor(rules.prizes, mineLast.rank) ?? null : null) : claim,
      claimed: me !== null && me.war_claimed === before.start,
      can_claim: typeof claim !== "string",
      why: typeof claim === "string" ? claim : "",
    },
    rules,
  };
}
