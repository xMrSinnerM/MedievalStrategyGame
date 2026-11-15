// The Warlord's Stronghold (a timed event for alliances, see data/events.json):
// while it runs, the stronghold stands near the castle of every member who
// was in their alliance when it rose. It is an ordinary camp in the player's
// camp list with `boss` set, so marches and battles treat it like any other,
// but it never rises a level: every defender slain there, win or lose, wears
// down the warlord's host, which the whole alliance shares. Each time the
// host is worn down the stronghold falls and every member who did their part
// claims a chest; your own tiers go by the defenders you slew. The host is
// not stored anywhere: it is the sum of what the alliance's members slew in
// this run (index.ts adds them up), so nothing can drift apart.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import type { CastleState } from "../../../server/rules/castle_state.ts";
import { activeEvents, lastBoss, type BossChest, type BossRules, type EventRules, type EventTime } from "../../../server/rules/events.ts";
import type { Report } from "../../../server/rules/marches.ts";
import { give } from "./horde.ts";
import { claimReward } from "./invasion.ts";
import type { PlayerState, World } from "./game.ts";

/** What a player has taken from the stronghold's last run: how many of their own tiers and how many fall chests. */
export interface BossState {
  claimed: number;
  falls: number;
}

export function emptyBoss(): BossState {
  return { claimed: 0, falls: 0 };
}

/** A player's alliance, as far as the stronghold cares: its id (null outside one) and when they joined. */
export interface BossMember {
  alliance_id: number | null;
  joined: number;
}

/** Whether this player storms the stronghold that rose at `start`: only members who were in their alliance by then. */
export function takesPart(member: BossMember | undefined, start: number): boolean {
  return member !== undefined && member.alliance_id !== null && member.joined <= start;
}

/**
 * The player's camps and stronghold score as of `t`: when a stronghold has
 * risen since they last played and they take part, it appears on the last
 * of the spots world.json lists around their castle, and their count and
 * claims start again. The stronghold of a run that is over leaves once no
 * army is marching to or from it. `offset` runs the event calendar that
 * many seconds ahead (local testing); runs are still keyed by their start
 * on the real clock.
 */
export function bossRises(stored: PlayerState, events: EventRules, world: World, t: number, offset = 0,
  member?: BossMember): PlayerState {
  const on = activeEvents(events, t + offset).find((e) => e.boss !== undefined);
  const start = on === undefined ? undefined : on.start - offset;
  const busy = new Set(stored.marches.map((m) => m.camp));
  const camps = stored.camps.filter((c) => c.boss === undefined || c.boss === start || busy.has(c.id));
  const key = stored.boss_key ?? 0;
  if (on?.boss !== undefined && start !== undefined && key !== start && takesPart(member, start)) {
    const rules = on.boss;
    const spot = (world.spots ?? []).findIndex(([x, y]) => x === stored.home_x && y === stored.home_y);
    const places = spot < 0 ? [] : world.invasion_spots?.[spot] ?? [];
    if (places.length > 0) {
      const place = places[places.length - 1];
      const keep = stored.castle.buildings.find((b) => b.type === "keep")?.level ?? 1;
      camps.push({
        id: `boss_${start}`,
        name: rules.name,
        position: [place[0], place[1]],
        level: rules.level + rules.level_per_keep * (keep - 1),
        defeats: 0,
        rebuilt_at: 0,
        boss: start,
        rebuild: rules.rally,
        until: on.end - offset,
      } satisfies CampData);
      return { ...stored, camps, boss_key: start, boss_damage: 0, boss: emptyBoss() };
    }
  }
  if (camps.length === stored.camps.length) return stored;
  return { ...stored, camps };
}

/** The stronghold's run the player's count belongs to, on the real clock, or undefined when that run is no longer the last one. */
export function playerBoss(events: EventRules, key: number, t: number, offset = 0): EventTime | undefined {
  const last = lastBoss(events, t + offset);
  if (last === undefined || last.start - offset !== key || key === 0) return undefined;
  return { ...last, start: last.start - offset, end: last.end - offset };
}

/** Defenders slain in these battle reports at the stronghold of the run starting at `key`. */
export function bossSlain(reports: Report[], key: number): number {
  let n = 0;
  for (const r of reports) if (r.boss !== undefined && r.boss === key) n += r.slain ?? 0;
  return n;
}

/** The warlord's host before fall number `fall` (0 is the first), for an alliance with `members` taking part. */
export function hostSize(rules: BossRules, members: number, fall: number): number {
  return Math.round((rules.host_base + rules.host_per_member * Math.max(1, members)) * Math.pow(rules.host_growth, fall));
}

/** How the alliance's host stands after `slain` defenders. */
export interface Host {
  slain: number;
  members: number;
  /** How often the stronghold has fallen, and how often it can. */
  falls: number;
  max_falls: number;
  /** The host standing now and how many of it are slain (both 0 once it has fallen for the last time). */
  size: number;
  down: number;
}

export function hostAfter(rules: BossRules, slain: number, members: number): Host {
  let falls = 0;
  let left = Math.max(0, slain);
  while (falls < rules.falls.length && left >= hostSize(rules, members, falls)) {
    left -= hostSize(rules, members, falls);
    falls += 1;
  }
  const done = falls >= rules.falls.length;
  return { slain, members, falls, max_falls: rules.falls.length, size: done ? 0 : hostSize(rules, members, falls), down: done ? 0 : left };
}

/**
 * Gives the player their own reward tier `tier` for the defenders they slew,
 * in order, while their run is the last one. Returns "" or why not.
 */
export function claimTier(castle: CastleState, boss: BossState, slain: number, run: EventTime | undefined, tier: unknown): string {
  if (run?.boss === undefined) return "Storm the Warlord's Stronghold with your alliance to earn rewards.";
  const why = claimReward(castle, slain, boss.claimed, run.boss.rewards, tier);
  if (why !== "") return why.replace("event points", "defenders slain");
  boss.claimed += 1;
  return "";
}

/**
 * Gives the player the chest for the next fall they haven't claimed: the
 * alliance has brought the stronghold down `falls` times (index.ts counts
 * them) and the player slew their share. Resources fill the storage (what
 * doesn't fit is lost). Returns "" or why not.
 */
export function claimFall(castle: CastleState, boss: BossState, slain: number, run: EventTime | undefined, falls: number): string {
  if (run?.boss === undefined) return "Storm the Warlord's Stronghold with your alliance to earn chests.";
  const chest: BossChest | undefined = run.boss.falls[boss.falls];
  if (chest === undefined) return "You have every chest.";
  if (boss.falls >= falls) return "Your alliance hasn't brought the stronghold down again yet.";
  if (slain < run.boss.min_damage) return `Slay ${run.boss.min_damage} defenders yourself to share in the chests.`;
  give(castle, chest);
  boss.falls += 1;
  return "";
}

/** A member's row, as index.ts reads it from the players table. */
export interface BossRow {
  name: string;
  boss_key: number;
  boss_damage: number;
  alliance_joined: number;
}

/**
 * How an alliance stands at the stronghold that rose at `key`: the host
 * after everything its members slew, and who slew how many (most first).
 * Only members who were in the alliance when it rose count, in the host's
 * size as in the slaying, so nobody can carry their count to another alliance.
 */
export function partyOf(rules: BossRules, rows: BossRow[], key: number): { host: Host; players: { name: string; points: number }[] } {
  const party = rows.filter((r) => Number(r.alliance_joined) <= key);
  const players = party.filter((r) => Number(r.boss_key) === key && Number(r.boss_damage) > 0)
    .map((r) => ({ name: String(r.name), points: Number(r.boss_damage) }))
    .sort((a, b) => b.points - a.points || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const slain = players.reduce((n, p) => n + p.points, 0);
  return { host: hostAfter(rules, slain, party.length), players };
}
