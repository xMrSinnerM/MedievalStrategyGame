// Quests: one story chain told by the castle's steward, and three daily
// tasks picked anew every day with a coffer for finishing them all. A port
// of scripts/economy/quest_book.gd; the numbers are in data/quests.json.
//
// Progress is read from the castle itself (its buildings, garrison and
// lifetime stats), so nothing has to be counted twice. Daily tasks count
// from the stats as they were when the day began (castle.quests.base).

import type { CastleState } from "./castle_state.ts";
import { Rng } from "./rng.ts";
import { godotHash, round, type Dict } from "./util.ts";

export const DAY = 86400;

export interface Reward {
  resources?: Dict;
  troops?: Dict;
  /** Siege tools, and treasure chests by kind (chests.ts). */
  tools?: Dict;
  chests?: Dict;
}

export interface Goal {
  kind: "building" | "soldiers" | "stat" | "production" | "storage" | "levels";
  type?: string;
  level?: number;
  count?: number;
  stat?: string;
  resource?: string;
  amount?: number;
}

export interface StoryQuest {
  chapter: number;
  title: string;
  text: string;
  goal: Goal;
  reward: Reward;
}

export interface DailyKind {
  text: string;
  /** The text when the target is 1. */
  one?: string;
  targets: number[];
  reward: Dict;
  /** Only picked for castles with a barracks. */
  barracks?: boolean;
}

export interface QuestRules {
  narrator: string;
  chapters: { title: string; intro: string }[];
  story: StoryQuest[];
  daily: {
    picks: number;
    scale: number[];
    kinds: Record<string, DailyKind>;
    coffer: { name: string; reward: Dict; streak_bonus: number; max_streak: number; streak_troops: Dict; chests?: Dict };
  };
}

export function dayOf(t: number): number {
  return Math.floor(t / DAY);
}

/** All the castle's building levels added up. */
export function totalLevels(castle: CastleState): number {
  let n = 0;
  for (const b of castle.buildings) n += b.level;
  return n;
}

/** [have, need] for a goal. */
export function progress(castle: CastleState, goal: Goal): [number, number] {
  const need = goal.kind === "building" ? goal.count ?? 1 : goal.amount ?? 0;
  let have = 0;
  switch (goal.kind) {
    case "building":
      have = castle.buildings.filter((b) => b.type === goal.type && b.level >= (goal.level ?? 1)).length;
      break;
    case "soldiers":
      have = castle.troopCount();
      break;
    case "stat":
      have = (castle.stats as unknown as Dict)[goal.stat ?? ""] ?? 0;
      break;
    case "production":
      have = castle.productionPerHour()[goal.resource ?? ""] ?? 0;
      break;
    case "storage":
      have = castle.storageCapacity();
      break;
    case "levels":
      have = totalLevels(castle);
      break;
  }
  return [Math.floor(have), need];
}

/** The keep level a day's targets and rewards are set by (1 to the last scale). */
function keepIndex(rules: QuestRules, keep: number): number {
  return Math.min(Math.max(keep, 1), rules.daily.scale.length) - 1;
}

/** The counts daily tasks are measured from. */
function snapshot(castle: CastleState): Dict {
  return { levels: totalLevels(castle), trained: castle.stats.trained, spent: castle.stats.spent,
    barons: castle.stats.barons, looted: castle.stats.looted };
}

/** The kinds of daily task for this day: random, but the same for the castle all day. */
export function pickDailies(castle: CastleState, rules: QuestRules, day: number): string[] {
  const open = Object.keys(rules.daily.kinds).filter((k) => !rules.daily.kinds[k].barracks || castle.barracksLevel() > 0);
  const rng = new Rng(day * 1000003 + godotHash(castle.castleName));
  const out: string[] = [];
  while (out.length < rules.daily.picks && open.length > 0) {
    out.push(open.splice(rng.randi() % open.length, 1)[0]);
  }
  return out;
}

/** Starts a new day's tasks if the day has turned. Returns whether it did. */
export function rollDay(castle: CastleState, rules: QuestRules, now: number): boolean {
  const day = dayOf(now);
  const q = castle.quests;
  if (q.day === day) return false;
  q.day = day;
  q.keep = keepIndex(rules, castle.keepLevel()) + 1;
  q.base = snapshot(castle);
  q.claimed = [];
  q.chest = false;
  q.picks = pickDailies(castle, rules, day);
  return true;
}

export function dailyTarget(rules: QuestRules, kind: string, keep: number): number {
  return rules.daily.kinds[kind].targets[keepIndex(rules, keep)];
}

/** [have, need] for today's daily task `index`. */
export function dailyProgress(castle: CastleState, rules: QuestRules, index: number): [number, number] {
  const q = castle.quests;
  const kind = q.picks[index];
  const now = kind === "levels" ? totalLevels(castle) : (castle.stats as unknown as Dict)[kind] ?? 0;
  return [Math.max(0, Math.floor(now - (q.base[kind] ?? 0))), dailyTarget(rules, kind, q.keep)];
}

export function dailyReward(rules: QuestRules, kind: string, keep: number): Reward {
  const scale = rules.daily.scale[keepIndex(rules, keep)];
  const resources: Dict = {};
  for (const [r, n] of Object.entries(rules.daily.kinds[kind].reward)) resources[r] = round(n * scale);
  return { resources };
}

/** The streak the coffer would count if opened today. */
export function cofferStreak(castle: CastleState, rules: QuestRules): number {
  const q = castle.quests;
  return q.chest_day === q.day - 1 ? Math.min(q.streak + 1, rules.daily.coffer.max_streak) : 1;
}

/** The days-in-a-row streak as it stands now (0 once a day was missed). */
export function currentStreak(castle: CastleState): number {
  const q = castle.quests;
  return q.chest_day >= q.day - 1 ? q.streak : 0;
}

export function cofferReward(rules: QuestRules, keep: number, streak: number): Reward {
  const c = rules.daily.coffer;
  const scale = rules.daily.scale[keepIndex(rules, keep)];
  const mult = scale * (1 + c.streak_bonus * (streak - 1));
  const resources: Dict = {};
  for (const [r, n] of Object.entries(c.reward)) resources[r] = round(n * mult);
  const reward: Reward = { resources };
  if (streak >= c.max_streak) {
    reward.troops = {};
    for (const [u, n] of Object.entries(c.streak_troops)) reward.troops[u] = round(n * scale);
  }
  if (c.chests) reward.chests = { ...c.chests };
  return reward;
}

/** The story quest being worked on, or undefined when the chain is done. */
export function currentStory(castle: CastleState, rules: QuestRules): StoryQuest | undefined {
  return rules.story[castle.quests.story];
}

/** Why this quest reward can't be claimed now ("" if it can). */
export function checkClaim(castle: CastleState, rules: QuestRules, kind: unknown, index: unknown): string {
  const q = castle.quests;
  if (kind === "story") {
    const quest = currentStory(castle, rules);
    if (quest === undefined) return "Every quest is done.";
    const [have, need] = progress(castle, quest.goal);
    return have >= need ? "" : "That quest isn't done yet.";
  }
  if (kind === "daily") {
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0 || index >= q.picks.length) return "There's no such task.";
    if (q.claimed.includes(index)) return "You already have that reward.";
    const [have, need] = dailyProgress(castle, rules, index);
    return have >= need ? "" : "That task isn't done yet.";
  }
  if (kind === "chest") {
    if (q.chest) return "You already opened today's coffer.";
    if (q.picks.length === 0 || q.claimed.length < q.picks.length) return "Finish today's tasks first.";
    return "";
  }
  return "There's no such quest.";
}

/** Gives a reward in full (even past the storage cap): resources, soldiers, siege tools and treasure chests. */
export function give(castle: CastleState, reward: Reward): void {
  for (const [r, n] of Object.entries(reward.resources ?? {})) {
    if (r in castle.resources) castle.resources[r] += n;
  }
  for (const [unit, n] of Object.entries(reward.troops ?? {})) {
    if (castle.rules.hasUnit(unit)) castle.troops[unit] = (castle.troops[unit] ?? 0) + n;
  }
  for (const [tool, n] of Object.entries(reward.tools ?? {})) {
    if (castle.rules.hasTool(tool)) castle.tools[tool] = (castle.tools[tool] ?? 0) + n;
  }
  for (const [kind, n] of Object.entries(reward.chests ?? {})) castle.chests.have[kind] = (castle.chests.have[kind] ?? 0) + n;
}

/** Claims the story quest, daily task `index` or the coffer ("story", "daily", "chest"). Returns "" or why not. */
export function claimQuest(castle: CastleState, rules: QuestRules, kind: unknown, index: unknown, now: number): string {
  rollDay(castle, rules, now);
  const why = checkClaim(castle, rules, kind, index);
  if (why !== "") return why;
  const q = castle.quests;
  if (kind === "story") {
    give(castle, currentStory(castle, rules)!.reward);
    q.story += 1;
  } else if (kind === "daily") {
    give(castle, dailyReward(rules, q.picks[index as number], q.keep));
    q.claimed.push(index as number);
  } else {
    const streak = cofferStreak(castle, rules);
    give(castle, cofferReward(rules, q.keep, streak));
    q.chest = true;
    q.streak = streak;
    q.chest_day = q.day;
  }
  return "";
}
