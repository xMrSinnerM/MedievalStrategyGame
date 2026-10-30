// Seasons: one a calendar month (UTC). The castle earns renown in a season
// from what it does in it, counted from its lifetime stats as they were when
// the season began. Renown milestones give rewards on a track; when the
// month ends, the players and alliances with the most renown win prizes and a
// title for that season. A port of scripts/economy/season_rules.gd; the
// numbers are in data/seasons.json.

import type { CastleState, SeasonLog } from "./castle_state.ts";
import { give, type Reward } from "./quests.ts";
import { clamp, round, type Dict } from "./util.ts";

export interface SeasonPrize {
  top: number;
  id: string;
  title: string;
  reward: Reward;
}

export interface SeasonRules {
  renown: Dict;
  scale: number[];
  track: { renown: number; reward: Reward }[];
  renowned: string;
  players: SeasonPrize[];
  alliances: SeasonPrize[];
}

/** The season (month) a time falls in, as months since year 0. */
export function seasonKey(t: number): number {
  const d = new Date(Math.floor(t) * 1000);
  return d.getUTCFullYear() * 12 + d.getUTCMonth();
}

export function seasonStart(key: number): number {
  return Date.UTC(Math.floor(key / 12), key % 12, 1) / 1000;
}

export function seasonEnd(key: number): number {
  return seasonStart(key + 1);
}

/** What renown is read from: a castle, or its saved JSON. */
type Counted = { buildings: { level: number }[]; stats: object; season: SeasonLog };

function snapshot(castle: Counted): Dict {
  const s = castle.stats as unknown as Dict;
  let levels = 0;
  for (const b of castle.buildings) levels += b.level;
  return { levels, trained: s.trained ?? 0, barons: s.barons ?? 0, looted: s.looted ?? 0,
    pvp_won: s.pvp_won ?? 0, pvp_held: s.pvp_held ?? 0 };
}

/** Renown over the castle's whole life, from its stats now (tournaments count what it gains). */
export function lifetimeRenown(castle: { buildings: { level: number }[]; stats: object }, rules: SeasonRules): number {
  const now = snapshot(castle as Counted);
  let total = 0;
  for (const [k, w] of Object.entries(rules.renown)) total += (now[k] ?? 0) * w;
  return total;
}

/** Renown earned this season. */
export function renown(castle: Counted, rules: SeasonRules): number {
  const now = snapshot(castle);
  const base = castle.season.base;
  let total = 0;
  for (const [k, w] of Object.entries(rules.renown)) {
    total += Math.max(0, (now[k] ?? 0) - (base[k] ?? now[k] ?? 0)) * w;
  }
  return Math.floor(total);
}

/** Starts the castle's new season once the month has turned, keeping what it earned in the one before. */
export function rollSeason(castle: CastleState, rules: SeasonRules, now: number): boolean {
  const key = seasonKey(now);
  const s = castle.season;
  if (s.key === key) return false;
  if (s.key >= 0) s.last = { key: s.key, points: renown(castle, rules), claimed: false };
  s.key = key;
  s.base = snapshot(castle);
  s.track = 0;
  return true;
}

export function trackReward(rules: SeasonRules, index: number, keep: number): Reward {
  const mult = rules.scale[clamp(keep, 1, rules.scale.length) - 1];
  const base = rules.track[index].reward;
  const resources: Dict = {};
  for (const [r, n] of Object.entries(base.resources ?? {})) resources[r] = round(n * mult);
  const out: Reward = { resources };
  if (base.troops) out.troops = { ...base.troops };
  if (base.chests) out.chests = { ...base.chests };
  return out;
}

/** Why the next track reward can't be claimed ("" if it can). */
export function checkTrack(castle: CastleState, rules: SeasonRules): string {
  const i = castle.season.track;
  if (i >= rules.track.length) return "Every reward this season is claimed.";
  if (renown(castle, rules) < rules.track[i].renown) return `You need ${rules.track[i].renown} renown for that.`;
  return "";
}

function honour(castle: CastleState, key: string): void {
  if (!castle.season.honours.includes(key)) castle.season.honours.push(key);
}

/** Claims the next track reward. Returns "" or why not. */
export function claimTrack(castle: CastleState, rules: SeasonRules, now: number): string {
  rollSeason(castle, rules, now);
  const why = checkTrack(castle, rules);
  if (why !== "") return why;
  const i = castle.season.track;
  give(castle, trackReward(rules, i, castle.keepLevel()));
  castle.season.track = i + 1;
  if (i + 1 === rules.track.length) honour(castle, `season:${castle.season.key}:renowned`);
  return "";
}

/** The first prize whose `top` covers this place (1 is first). */
export function prizeFor(prizes: SeasonPrize[], place: number): SeasonPrize | undefined {
  return place < 1 ? undefined : prizes.find((p) => place <= p.top);
}

export function checkPrize(castle: CastleState): string {
  const last = castle.season.last;
  if (!("key" in last) || last.points <= 0) return "You earned no renown last season.";
  if (last.claimed) return "You already have last season's prize.";
  return "";
}

/** Claims last season's prizes for your place and your alliance's. Returns "" or why not. */
export function claimPrize(castle: CastleState, rules: SeasonRules, place: number, alliancePlace: number, now: number): string {
  rollSeason(castle, rules, now);
  const why = checkPrize(castle);
  if (why !== "") return why;
  const last = castle.season.last as { key: number; points: number; claimed: boolean };
  for (const p of [prizeFor(rules.players, place), prizeFor(rules.alliances, alliancePlace)]) {
    if (!p) continue;
    give(castle, p.reward);
    honour(castle, `season:${last.key}:${p.id}`);
  }
  last.claimed = true;
  return "";
}

/** The ranking columns of the players table, from a castle. */
export function seasonColumns(castle: Counted, rules: SeasonRules) {
  const last = castle.season.last;
  return {
    season_key: castle.season.key, season_points: renown(castle, rules),
    last_season_key: "key" in last ? last.key : -1, last_season_points: "key" in last ? last.points : 0,
  };
}

/** Your place among players (1 is first) in season `key`, given everyone's [key, points, last key, last points]. */
export function placeIn(rows: { season_key: number; season_points: number; last_season_key: number; last_season_points: number }[],
  key: number, points: number): number {
  if (points <= 0) return 0;
  let ahead = 0;
  for (const r of rows) {
    if ((r.season_key === key && r.season_points > points) || (r.last_season_key === key && r.last_season_points > points)) ahead++;
  }
  return ahead + 1;
}

/** Alliances ranked by their members' renown in season `key`: [[alliance, points], ...], best first. */
export function allianceStandings(rows: { alliance_id: number | null; season_key: number; season_points: number;
  last_season_key: number; last_season_points: number }[], key: number): [number, number][] {
  const sums = new Map<number, number>();
  for (const r of rows) {
    if (r.alliance_id === null || r.alliance_id === undefined) continue;
    const pts = r.season_key === key ? r.season_points : r.last_season_key === key ? r.last_season_points : 0;
    if (pts > 0) sums.set(Number(r.alliance_id), (sums.get(Number(r.alliance_id)) ?? 0) + pts);
  }
  return [...sums.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
}
