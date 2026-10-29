// Achievements and titles: lifetime goals in three tiers. A tier is earned
// for good the moment its count is reached, gives a reward to claim and a
// title to show on the castle. A port of scripts/economy/achievements.gd; the
// numbers are in data/achievements.json.
//
// Progress is read from the castle itself, like the quests. Earned tiers are
// kept in castle.achievements, so a count that falls again doesn't take them away.

import type { CastleState } from "./castle_state.ts";
import { give, totalLevels, type Reward } from "./quests.ts";
import type { Dict } from "./util.ts";

export interface Achievement {
  id: string;
  name: string;
  text: string;
  /** levels, keep, stat:<name>, story, streak, research, commander or soldiers. */
  measure: string;
  needs: number[];
  titles: string[];
  /** Only counts in the online game. */
  online?: boolean;
}

export interface AchievementRules {
  points: number[];
  tier_names: string[];
  rewards: Reward[];
  list: Achievement[];
}

export function findAchievement(rules: AchievementRules, id: unknown): Achievement | undefined {
  return rules.list.find((a) => a.id === id);
}

/** The achievements that count in this game (online ones only online). */
export function shown(rules: AchievementRules, online: boolean): Achievement[] {
  return rules.list.filter((a) => online || !a.online);
}

/** Where the castle stands now on what this achievement counts. */
export function measure(castle: CastleState, def: Achievement): number {
  const m = def.measure;
  if (m.startsWith("stat:")) return Math.floor(Number((castle.stats as unknown as Dict)[m.slice(5)] ?? 0));
  switch (m) {
    case "levels":
      return totalLevels(castle);
    case "keep":
      return castle.keepLevel();
    case "story":
      return castle.quests.story;
    case "streak":
      return castle.quests.streak;
    case "research":
      return Object.values(castle.research).reduce((n, v) => n + v, 0);
    case "commander":
      return castle.armoury.commanders.reduce((best, c) => Math.max(best, c.level), 0);
    case "soldiers":
      return castle.troopCount();
  }
  return 0;
}

/** How many tiers this count reaches. */
export function reached(def: Achievement, value: number): number {
  return def.needs.filter((need) => value >= need).length;
}

const earned = (castle: CastleState, id: string) => castle.achievements.tiers[id] ?? 0;
const claimedTiers = (castle: CastleState, id: string) => castle.achievements.claimed[id] ?? 0;

/** Records the tiers reached since last time; returns them as [id, tier] pairs (tier from 1). */
export function note(castle: CastleState, rules: AchievementRules, online: boolean): [string, number][] {
  const fresh: [string, number][] = [];
  for (const def of shown(rules, online)) {
    const now = reached(def, measure(castle, def));
    const had = earned(castle, def.id);
    if (now > had) {
      castle.achievements.tiers[def.id] = now;
      for (let t = had + 1; t <= now; t++) fresh.push([def.id, t]);
    }
  }
  return fresh;
}

/** Why the next reward of this achievement can't be claimed ("" if it can). */
export function checkClaim(castle: CastleState, rules: AchievementRules, id: unknown): string {
  if (findAchievement(rules, id) === undefined) return "There's no such achievement.";
  const key = id as string;
  if (earned(castle, key) === 0) return "You haven't earned that yet.";
  if (claimedTiers(castle, key) >= earned(castle, key)) return "You already have that reward.";
  return "";
}

/** Gives the next earned reward of this achievement. Returns "" or why not. */
export function claimAchievement(castle: CastleState, rules: AchievementRules, id: unknown, online: boolean): string {
  note(castle, rules, online);
  const why = checkClaim(castle, rules, id);
  if (why !== "") return why;
  const key = id as string;
  const tier = claimedTiers(castle, key) + 1;
  give(castle, rules.rewards[tier - 1] ?? {});
  castle.achievements.claimed[key] = tier;
  return "";
}

/** Achievement points: the points of every tier earned. */
export function score(castle: CastleState, rules: AchievementRules): number {
  let n = 0;
  for (const tiers of Object.values(castle.achievements.tiers)) {
    for (let t = 0; t < Math.min(tiers, rules.points.length); t++) n += rules.points[t];
  }
  return n;
}

/** "the Builder" for "builder:1"; "" for no title or one that doesn't exist. */
export function titleText(rules: AchievementRules, key: unknown): string {
  if (typeof key !== "string") return "";
  const m = /^([a-z_]+):(\d+)$/.exec(key);
  if (!m) return "";
  const titles = findAchievement(rules, m[1])?.titles ?? [];
  const tier = Number(m[2]);
  return tier >= 1 && tier <= titles.length ? titles[tier - 1] : "";
}

/** Shows a title on the castle ("" takes it off). Returns "" or why not. */
export function setTitle(castle: CastleState, rules: AchievementRules, key: unknown): string {
  if (key === "") {
    castle.achievements.title = "";
    return "";
  }
  if (titleText(rules, key) === "") return "There's no such title.";
  const [id, tier] = (key as string).split(":");
  if (earned(castle, id) < Number(tier)) return "You haven't earned that title yet.";
  castle.achievements.title = key as string;
  return "";
}
