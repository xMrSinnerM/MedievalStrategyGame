// Weekly alliance tournaments (data/tournaments.json): a knockout bracket
// between the mightiest alliances, drawn when the week starts. In each match
// both alliances score the renown their members earn while it lasts
// (data/seasons.json); the higher score goes through. Once the final is over,
// every member of an entered alliance claims a prize by how far it got.
// This file has the rules without the database: index.ts (and the local
// server) store the bracket and call in here.

import type { CastleState } from "../../../server/rules/castle_state.ts";
import { lifetimeRenown, type SeasonRules } from "../../../server/rules/seasons.ts";
import { givePrize, prizeFor, type WarPrize } from "./wars.ts";

export interface TourneyRules {
  /** A week starts on `day` (1 = Monday ... 7 = Sunday) at `hour` UTC. */
  day: number;
  hour: number;
  /** How long each round lasts, in hours, one after another from the week's start. */
  rounds: number[];
  /** At most this many alliances (a power of 2). */
  size: number;
  min_members: number;
  /** Best place first: 1 the winner, 2 the finalist, 4 the semi-finalists, 8 the quarter-finalists. */
  prizes: WarPrize[];
}

/** An alliance in the bracket, with its seed (1 is the mightiest). */
export interface Entrant {
  id: number;
  name: string;
  tag: string;
  seed: number;
}

/** A match: the two alliances (null for a bye, 0 while the match before is undecided), their scores and who went through (null until it's decided). */
export interface Match {
  a: number | null;
  b: number | null;
  a_points: number;
  b_points: number;
  winner: number | null;
}

/** A round of the bracket: when it's played and its matches. */
export interface Round {
  name: string;
  start: number;
  end: number;
  matches: Match[];
}

/** What the tournament needs to know about a player: their alliance and when they joined it, and the week whose prize they took. */
export interface TourneyMember {
  alliance_id: number | null;
  joined: number;
  claimed: number;
}

const DAY = 86400;
const HOUR = 3600;
const WEEK = 7 * DAY;
// 1970-01-01 was a Thursday, so Monday 00:00 UTC of that week was 3 days earlier.
const MONDAY = -3 * DAY;
const NAMES = ["Final", "Semi-finals", "Quarter-finals", "Round of 16", "Round of 32"];

/** The start of the tournament week `t` falls in. */
export function weekAt(rules: TourneyRules, t: number): number {
  const first = MONDAY + (rules.day - 1) * DAY + rules.hour * HOUR;
  return first + Math.floor((t - first) / WEEK) * WEEK;
}

/** How many places a bracket for `n` alliances has: the smallest power of 2 that fits them (at most `size`; 0 under 2). */
export function slots(rules: TourneyRules, n: number): number {
  if (n < 2) return 0;
  let s = 2;
  while (s < n && s < rules.size) s *= 2;
  return s;
}

/** The order seeds stand in the first round, so the best meet last: 1, 8, 4, 5, 2, 7, 3, 6 for 8. */
export function seedOrder(size: number): number[] {
  let order = [1];
  while (order.length < size) {
    const n = order.length * 2;
    order = order.flatMap((s) => [s, n + 1 - s]);
  }
  return order;
}

/** The rounds a bracket of `size` places plays: the last ones of the week's, ending with the final. */
export function schedule(rules: TourneyRules, week: number, size: number): { name: string; start: number; end: number }[] {
  const all: { start: number; end: number }[] = [];
  let t = week;
  for (const hours of rules.rounds) {
    all.push({ start: t, end: t + hours * HOUR });
    t += hours * HOUR;
  }
  const count = Math.min(all.length, Math.round(Math.log2(Math.max(size, 1))));
  const used = all.slice(all.length - count);
  return used.map((r, i) => ({ name: NAMES[count - 1 - i] ?? `Round ${i + 1}`, ...r }));
}

/** The round on at `t` (its start, used as the key renown is counted under), or 0 between rounds. */
export function roundKey(rules: TourneyRules, t: number): number {
  const week = weekAt(rules, t);
  let start = week;
  for (const hours of rules.rounds) {
    const end = start + hours * HOUR;
    if (t >= start && t < end) return start;
    start = end;
  }
  return 0;
}

/** Draws the bracket: the mightiest alliances with enough members, seeded by might. */
export function draw(rules: TourneyRules, alliances: { id: number; name: string; tag: string; members: number; might: number }[]): Entrant[] {
  const fit = alliances.filter((a) => a.members >= rules.min_members)
    .sort((a, b) => b.might - a.might || a.id - b.id).slice(0, rules.size);
  if (fit.length < 2) return [];
  return fit.map((a, i) => ({ id: a.id, name: a.name, tag: a.tag, seed: i + 1 }));
}

/** Who goes through: the one with a bye's opponent, else the higher score, a tie going to the higher seed. */
export function decide(m: Match, seeds: Map<number, number>): number | null {
  if (m.a === null) return m.b;
  if (m.b === null) return m.a;
  if (m.a_points !== m.b_points) return m.a_points > m.b_points ? m.a : m.b;
  return (seeds.get(m.a) ?? 99) <= (seeds.get(m.b) ?? 99) ? m.a : m.b;
}

/**
 * The bracket as it stands at `t`: every round with its matches. A round
 * that has started takes its scores from `scores(roundStart)` (each
 * alliance's renown in it); one that has ended is decided. Later rounds
 * fill in with the winners as they're known.
 */
export function bracket(rules: TourneyRules, week: number, entrants: Entrant[], t: number,
  scores: (start: number) => Map<number, number>): Round[] {
  const size = slots(rules, entrants.length);
  if (size === 0) return [];
  const bySeed = new Map(entrants.map((e) => [e.seed, e.id]));
  const seeds = new Map(entrants.map((e) => [e.id, e.seed]));
  let line: (number | null)[] = seedOrder(size).map((s) => bySeed.get(s) ?? null);
  const out: Round[] = [];
  for (const r of schedule(rules, week, size)) {
    const started = t >= r.start;
    const points = started ? scores(r.start) : new Map<number, number>();
    const matches: Match[] = [];
    for (let i = 0; i < line.length; i += 2) {
      const m: Match = { a: line[i], b: line[i + 1], a_points: 0, b_points: 0, winner: null };
      if (m.a) m.a_points = Math.floor(points.get(m.a) ?? 0);
      if (m.b) m.b_points = Math.floor(points.get(m.b) ?? 0);
      // A bye goes through at once; a real match once its round is over.
      if (m.a !== 0 && m.b !== 0 && (m.a === null || m.b === null || t >= r.end)) m.winner = decide(m, seeds);
      matches.push(m);
    }
    out.push({ ...r, matches });
    // An undecided match leaves its place in the next round unknown (0); two byes leave a bye.
    line = matches.map((m) => m.winner ?? (m.a === null && m.b === null ? null : 0));
  }
  return out;
}

/** How far an alliance got: 1 for the winner, 2 the finalist, 4 out in the semi-finals, ...; 0 if not in it or not over yet. */
export function placeOf(rounds: Round[], id: number): number {
  if (rounds.length === 0) return 0;
  const final = rounds[rounds.length - 1].matches[0];
  if (final.winner === null) return 0;
  if (final.winner === id) return 1;
  for (let i = rounds.length - 1; i >= 0; i--) {
    for (const m of rounds[i].matches) {
      if ((m.a === id || m.b === id) && m.winner !== null && m.winner !== id) return 2 ** (rounds.length - i);
    }
  }
  return 0;
}

/** The last tournament whose final is over by `t` (its week), counting this week's once it's done. */
export function claimableWeek(rules: TourneyRules, t: number): number {
  const week = weekAt(rules, t);
  const total = rules.rounds.reduce((s, h) => s + h * HOUR, 0);
  return t >= week + total ? week : week - WEEK;
}

/**
 * The prize this player can claim for a finished tournament (`rounds`,
 * drawn at `week`), from how far their alliance got, or why not.
 */
export function checkClaim(rules: TourneyRules, me: TourneyMember, week: number, rounds: Round[]): WarPrize | string {
  if (me.alliance_id === null) return "Join an alliance to play in the tournaments.";
  if (rounds.length === 0) return "The last tournament didn't take place: it needs two alliances.";
  if (me.claimed === week) return "You already have your tournament prize.";
  const place = placeOf(rounds, me.alliance_id);
  if (place === 0) return rounds.some((r) => r.matches.some((m) => m.a === me.alliance_id || m.b === me.alliance_id))
    ? "The tournament isn't over yet." : "Your alliance wasn't in the tournament.";
  if (me.joined > week) return "You joined your alliance after the bracket was drawn.";
  return prizeFor(rules.prizes, place) ?? "There's no prize for that place.";
}

export { givePrize };

// --- Renown counted for the round on, kept in the castle --------------------

/** Renown this castle has earned in the round it's counting. */
export function roundPoints(castle: CastleState, seasons: SeasonRules): number {
  return castle.tourney.key > 0 ? Math.max(0, Math.floor(lifetimeRenown(castle, seasons) - castle.tourney.base)) : 0;
}

/** Starts counting the round on at `now`, keeping what was earned in the one before. */
export function rollTourney(castle: CastleState, rules: TourneyRules, seasons: SeasonRules, now: number): boolean {
  const key = roundKey(rules, now);
  const tr = castle.tourney;
  if (tr.key === key) return false;
  if (tr.key > 0) {
    tr.last_key = tr.key;
    tr.last_points = roundPoints(castle, seasons);
  }
  tr.key = key;
  tr.base = lifetimeRenown(castle, seasons);
  return true;
}

/** The tournament columns of the players table, from a castle. */
export function tourneyColumns(castle: CastleState, seasons: SeasonRules) {
  return { tourney_key: castle.tourney.key, tourney_points: roundPoints(castle, seasons),
    last_tourney_key: castle.tourney.last_key, last_tourney_points: castle.tourney.last_points };
}

/** A player row as the tournament reads it. */
export interface TourneyRow {
  alliance_id: number | null;
  alliance_joined: number;
  tourney_key: number;
  tourney_points: number;
  last_tourney_key: number;
  last_tourney_points: number;
}

/** Each alliance's renown in the round that started at `start`, from its members who joined before it began. */
export function roundScores(rows: TourneyRow[], start: number): Map<number, number> {
  const out = new Map<number, number>();
  for (const r of rows) {
    if (r.alliance_id === null || r.alliance_id === undefined || Number(r.alliance_joined) > start) continue;
    const pts = Number(r.tourney_key) === start ? Number(r.tourney_points)
      : Number(r.last_tourney_key) === start ? Number(r.last_tourney_points) : 0;
    if (pts > 0) out.set(Number(r.alliance_id), (out.get(Number(r.alliance_id)) ?? 0) + pts);
  }
  return out;
}

/**
 * What the tournament screen shows: this week's bracket (or why there is
 * none), the round on, the player's alliance and the prize they can claim
 * from the last finished tournament.
 */
export function tourneyBoard(rules: TourneyRules, t: number, week: number, entrants: Entrant[], rounds: Round[],
  me: TourneyMember | null, prize: { week: number; rounds: Round[] } | null) {
  const claim = me === null ? "Found your castle first." : prize === null ? "No tournament has finished yet."
    : checkClaim(rules, me, prize.week, prize.rounds);
  const place = me?.alliance_id != null && prize ? placeOf(prize.rounds, me.alliance_id) : 0;
  return {
    week, end: week + WEEK, now: t,
    entrants,
    rounds,
    mine: me?.alliance_id ?? null,
    prize: {
      place,
      prize: typeof claim === "string" ? (place > 0 ? prizeFor(rules.prizes, place) ?? null : null) : claim,
      claimed: me !== null && prize !== null && me.claimed === prize.week,
      can_claim: typeof claim !== "string",
      why: typeof claim === "string" ? claim : "",
    },
    rules,
  };
}
