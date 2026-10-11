// Timed events: a weekly calendar from data/events.json, the same for every
// player. Whether an event is on is a pure function of the time, so the
// server needs no timers: it asks what is on when it resolves a battle.

/** One weekly event: starts on `day` (1 = Monday ... 7 = Sunday) at `hour` UTC and lasts `hours`. */
export interface WeeklyEvent {
  id: string;
  name: string;
  description: string;
  day: number;
  hour: number;
  hours: number;
  effects: Record<string, number>;
  /** Invader camps near every castle while the event runs (see invasion.ts). */
  invasion?: InvasionRules;
}

/** How a Baron Invasion goes, from data/events.json. */
export interface InvasionRules {
  camps: number;
  names: string[];
  /** The first camp's level is 1 + this per keep level above 1; each next camp is a level higher. */
  level_per_keep: number;
  /** Event points for a win: this times the camp's level. */
  points_per_level: number;
  /** Seconds a beaten invader camp rebuilds. */
  rebuild: number;
  /** Reward tiers, claimed in order once you have their points. */
  rewards?: RewardTier[];
}

/** What an event reward tier gives: resources for your storage and soldiers for your garrison. */
export interface RewardTier {
  points: number;
  resources?: Record<string, number>;
  troops?: Record<string, number>;
}

export interface EventRules {
  weekly: WeeklyEvent[];
  /** Changes the game owner made to the calendar (see withOverrides). */
  overrides?: EventOverride[];
}

/**
 * The game owner's change to the calendar: the weekly event `event` runs from
 * `start` to `end`. With the start of a scheduled run it moves that run's end
 * (stopping it early); any other start adds an extra run.
 */
export interface EventOverride {
  event: string;
  start: number;
  end: number;
}

/** An event on the calendar, with its start and end (Unix seconds). */
export interface EventTime {
  id: string;
  name: string;
  description: string;
  effects: Record<string, number>;
  invasion?: InvasionRules;
  start: number;
  end: number;
}

const DAY = 86400;
const WEEK = 7 * DAY;
// 1970-01-01 was a Thursday, so Monday 00:00 UTC of that week was 3 days earlier.
const MONDAY = -3 * DAY;

/** The most recent start of this event at or before `t`. */
export function lastStart(e: WeeklyEvent, t: number): number {
  const offset = (e.day - 1) * DAY + e.hour * 3600;
  const weekStart = MONDAY + Math.floor((t - MONDAY) / WEEK) * WEEK;
  const start = weekStart + offset;
  return start <= t ? start : start - WEEK;
}

function at(e: WeeklyEvent, start: number): EventTime {
  const out: EventTime = { id: e.id, name: e.name, description: e.description, effects: e.effects, start, end: start + e.hours * 3600 };
  if (e.invasion !== undefined) out.invasion = e.invasion;
  return out;
}

/** The calendar with the game owner's overrides. */
export function withOverrides(rules: EventRules, overrides: EventOverride[]): EventRules {
  return { ...rules, overrides };
}

/** The runs of every event that started at or before `t` and may still matter: the last scheduled one and the owner's. */
function runs(rules: EventRules, t: number): EventTime[] {
  const overrides = rules.overrides ?? [];
  const out: EventTime[] = [];
  for (const e of rules.weekly) {
    const start = lastStart(e, t);
    const run = at(e, start);
    const moved = overrides.find((o) => o.event === e.id && o.start === start);
    if (moved !== undefined) run.end = moved.end;
    out.push(run);
    for (const o of overrides) {
      if (o.event !== e.id || o.start === start || o.start > t) continue;
      out.push({ ...at(e, o.start), end: o.end });
    }
  }
  return out;
}

/** The events that are on at `t`. */
export function activeEvents(rules: EventRules, t: number): EventTime[] {
  return runs(rules, t).filter((e) => e.start <= t && t < e.end);
}

/** The events that start after `t`, soonest first (one per weekly event). */
export function upcomingEvents(rules: EventRules, t: number): EventTime[] {
  return rules.weekly.map((e) => at(e, lastStart(e, t) + WEEK)).sort((a, b) => a.start - b.start);
}

/** The Baron Invasion on at `t`, or else the last one to have started (undefined if there is none on the calendar). */
export function lastInvasion(rules: EventRules, t: number): EventTime | undefined {
  let best: EventTime | undefined;
  for (const time of runs(rules, t)) {
    if (time.invasion === undefined || time.start > t) continue;
    if (best === undefined || time.start > best.start) best = time;
  }
  return best;
}

/** The product of an effect over the events on at `t` (1 when none). */
export function effectAt(rules: EventRules, t: number, effect: string): number {
  let factor = 1;
  for (const e of activeEvents(rules, t)) factor *= e.effects[effect] ?? 1;
  return factor;
}

/** What the game shows: the events on now and the next ones. */
export function eventsView(rules: EventRules, t: number) {
  return { active: activeEvents(rules, t), upcoming: upcomingEvents(rules, t) };
}
