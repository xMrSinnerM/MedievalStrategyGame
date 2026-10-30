// The Royal Gift: a reward for coming back each day (00:00 UTC, like the
// daily tasks). A week of gifts that grow towards day 7; missing a day starts
// the week over, and every full week in a row makes them a little bigger. A
// port of scripts/economy/login_rewards.gd; the numbers are in data/login.json.

import type { CastleState } from "./castle_state.ts";
import { give, type Reward } from "./quests.ts";
import { clamp, round, type Dict } from "./util.ts";

export const DAY = 86400;

export interface LoginRules {
  name: string;
  giver: string;
  line: string;
  scale: number[];
  week_bonus: number;
  max_weeks: number;
  days: Reward[];
}

export function dayOf(t: number): number {
  return Math.floor(t / DAY);
}

export function takenToday(castle: CastleState, now: number): boolean {
  return castle.login.last === dayOf(now);
}

/** Days in a row as it stands now (0 once a day was missed). */
export function currentStreak(castle: CastleState, now: number): number {
  return castle.login.last >= dayOf(now) - 1 ? castle.login.streak : 0;
}

/** The days in a row today's gift counts (or counted, once taken). */
export function nextStreak(castle: CastleState, now: number): number {
  const { last, streak } = castle.login;
  const today = dayOf(now);
  if (last === today) return streak;
  return last === today - 1 ? streak + 1 : 1;
}

/** The day of the week's gifts (0 to 6) a streak lands on. */
export function weekDay(rules: LoginRules, streak: number): number {
  return (Math.max(streak, 1) - 1) % Math.max(rules.days.length, 1);
}

/** Full weeks in a row before this day, as far as they add to the gifts. */
export function weeksKept(rules: LoginRules, streak: number): number {
  return Math.min(Math.floor((Math.max(streak, 1) - 1) / Math.max(rules.days.length, 1)), rules.max_weeks);
}

/** The gift on day `day` of the week (0 to 6) for this keep level, after `weeks` full weeks in a row. */
export function loginReward(rules: LoginRules, day: number, keep: number, weeks = 0): Reward {
  const mult = rules.scale[clamp(keep, 1, rules.scale.length) - 1] * (1 + rules.week_bonus * weeks);
  const base = rules.days[clamp(day, 0, rules.days.length - 1)];
  const resources: Dict = {};
  for (const [r, n] of Object.entries(base.resources ?? {})) resources[r] = round(n * mult);
  const out: Reward = { resources };
  if (base.troops) out.troops = { ...base.troops };
  if (base.chests) out.chests = { ...base.chests };
  return out;
}

export function todayReward(castle: CastleState, rules: LoginRules, now: number): Reward {
  const streak = nextStreak(castle, now);
  return loginReward(rules, weekDay(rules, streak), castle.keepLevel(), weeksKept(rules, streak));
}

/** Why the gift can't be taken now ("" if it can). */
export function checkLogin(castle: CastleState, rules: LoginRules, now: number): string {
  if (rules.days.length === 0) return "There's no gift.";
  if (takenToday(castle, now)) return "You already have today's gift. Come back tomorrow.";
  return "";
}

/** Takes today's gift. Returns "" or why not. */
export function claimLogin(castle: CastleState, rules: LoginRules, now: number): string {
  const why = checkLogin(castle, rules, now);
  if (why !== "") return why;
  const streak = nextStreak(castle, now);
  give(castle, todayReward(castle, rules, now));
  castle.login = { last: dayOf(now), streak, total: castle.login.total + 1 };
  return "";
}
