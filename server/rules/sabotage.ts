// Spies and sabotage: hired agents sent into a robber baron's camp or another
// player's castle, to steal, burn the stores or weaken the walls for a while.
// A port of scripts/economy/sabotage_rules.gd; the numbers are in
// data/sabotage.json. Missions against players are decided here.

import { carried, type CampData } from "./baron_camp.ts";
import type { BaronRules } from "./baron_rules.ts";
import type { CastleState } from "./castle_state.ts";
import { Rng } from "./rng.ts";
import { godotHash, type Dict } from "./util.ts";

export interface SabotageRules {
  agent_gold: number;
  max_agents: number;
  cooldown_hours: number;
  chance: { base: number; per_agent: number; per_camp_level: number; per_keep: number; min: number; max: number };
  scale: number[];
  carry_per_agent: number;
  steal_share: number;
  burn_share: number;
  walls_cut: number;
  walls_hours: number;
  missions: Record<string, { name: string; text: string; players_only?: boolean }>;
}

export function cost(rules: SabotageRules, agents: number): Dict {
  return { gold: rules.agent_gold * agents };
}

function clampChance(rules: SabotageRules, c: number): number {
  return Math.min(Math.max(c, rules.chance.min), rules.chance.max);
}

export function campChance(rules: SabotageRules, agents: number, campLevel: number): number {
  return clampChance(rules, rules.chance.base + rules.chance.per_agent * agents - rules.chance.per_camp_level * (campLevel - 1));
}

export function playerChance(rules: SabotageRules, agents: number, myKeep: number, theirKeep: number): number {
  return clampChance(rules, rules.chance.base + rules.chance.per_agent * agents - rules.chance.per_keep * Math.max(0, theirKeep - myKeep));
}

export function carry(rules: SabotageRules, agents: number, keep: number): number {
  return rules.carry_per_agent * agents * rules.scale[Math.min(Math.max(keep, 1), rules.scale.length) - 1];
}

export const campKey = (id: string) => `camp:${id}`;
export const playerKey = (name: string) => `player:${name}`;

/** Seconds until agents can be sent to this target again (0 if now). */
export function waitLeft(castle: CastleState, rules: SabotageRules, key: string, now: number): number {
  const last = Object.hasOwn(castle.sabotage.sent, key) ? castle.sabotage.sent[key] : -Infinity;
  return Math.max(0, last + rules.cooldown_hours * 3600 - now);
}

/** Why these agents can't go now ("" if they can). */
export function checkSabotage(castle: CastleState, rules: SabotageRules, key: string, mission: unknown, agents: unknown, now: number,
  player = false): string {
  if (typeof mission !== "string" || !Object.hasOwn(rules.missions, mission)) return "There's no such mission.";
  if (!player && rules.missions[mission].players_only) return "Camps keep no stores worth burning.";
  if (typeof agents !== "number" || !Number.isInteger(agents) || agents < 1 || agents > rules.max_agents) {
    return `Send between 1 and ${rules.max_agents} agents.`;
  }
  const wait = waitLeft(castle, rules, key, now);
  if (wait > 0) return `Your agents there are lying low for another ${Math.ceil(wait / 60)} minutes.`;
  if (!castle.canAfford(cost(rules, agents))) return `Not enough gold to hire ${agents} agents.`;
  return "";
}

/** Pays the agents and remembers when they went (forgetting old targets). */
export function sendAgents(castle: CastleState, rules: SabotageRules, key: string, agents: number, now: number): void {
  castle.pay(cost(rules, agents));
  const sent: Dict = {};
  for (const [k, t] of Object.entries(castle.sabotage.sent)) if (t + rules.cooldown_hours * 3600 > now) sent[k] = t;
  sent[key] = now;
  castle.sabotage.sent = sent;
  castle.sabotage.count += 1;
}

/** The mission's luck: from the castle, the target and how many missions it has sent, so the game can tell too. */
export function seedFor(castle: CastleState, key: string, agents: number): number {
  return godotHash(castle.castleName) + (godotHash(key) % 100003) + castle.sabotage.count * 7919 + agents * 17;
}

export function roll(chance: number, seed: number): boolean {
  return new Rng(seed).randf() < chance;
}

export interface SabotageResult {
  error: string;
  success?: boolean;
  chance?: number;
  /** Resources the agents brought home. */
  stolen?: Dict;
  /** Resources that burned in the target's stores. */
  burned?: Dict;
}

/** Sends agents into a camp (online camps live in the player's state). */
export function againstCamp(castle: CastleState, camp: CampData, barons: BaronRules, rules: SabotageRules, mission: unknown,
  agents: unknown, now: number): SabotageResult {
  const key = campKey(camp.id);
  const why = checkSabotage(castle, rules, key, mission, agents, now);
  if (why !== "") return { error: why };
  const n = agents as number;
  const chance = campChance(rules, n, camp.level);
  const success = roll(chance, seedFor(castle, key, n));
  sendAgents(castle, rules, key, n, now);
  let stolen: Dict = {};
  if (success) {
    if (mission === "steal") {
      const stock: Dict = {};
      for (const [r, x] of Object.entries(barons.forCamp(camp).loot(camp.level))) stock[r] = Math.floor(x * rules.steal_share);
      stolen = carried(stock, carry(rules, n, castle.keepLevel()));
      for (const [r, x] of Object.entries(stolen)) castle.resources[r] = (castle.resources[r] ?? 0) + x;
    } else {
      camp.weak_until = now + rules.walls_hours * 3600;
      camp.weak_cut = rules.walls_cut;
    }
  }
  return { error: "", success, stolen, chance };
}

/** How much of a resource agents carry off from this castle. */
export function stealFrom(rules: SabotageRules, their: CastleState, resource: string, agents: number, myKeep: number): number {
  if (!Object.hasOwn(their.resources, resource)) return 0;
  const free = Math.max(their.resources[resource] - their.hidden(), 0);
  return Math.min(carry(rules, agents, myKeep), Math.floor(free * rules.steal_share));
}

/** What burning the stores destroys: a share of every resource above the hidden cellars. */
export function burned(rules: SabotageRules, their: CastleState): Dict {
  const out: Dict = {};
  for (const [r, x] of Object.entries(their.resources)) {
    const n = Math.floor(Math.max(x - their.hidden(), 0) * rules.burn_share);
    if (n > 0) out[r] = n;
  }
  return out;
}

/** What's left of a castle's wall strength at time t after sabotage. */
export function wallsFactor(castle: CastleState, t: number): number {
  return castle.sabotage.walls_until > t ? 1 - castle.sabotage.walls_cut : 1;
}

/**
 * Carries out a mission against a player whose castle is `their` (as of now):
 * what the agents take or destroy. The caller saves both castles. The
 * attacker pays and the chance is rolled in act(); this is the target's side.
 */
export function hitPlayer(rules: SabotageRules, their: CastleState, mission: string, resource: string, agents: number, myKeep: number,
  now: number): { stolen: Dict; burned: Dict } {
  if (mission === "steal") {
    const n = stealFrom(rules, their, resource, agents, myKeep);
    if (n > 0) their.resources[resource] -= n;
    return { stolen: n > 0 ? { [resource]: n } : {}, burned: {} };
  }
  if (mission === "burn_stores") {
    const b = burned(rules, their);
    for (const [r, n] of Object.entries(b)) their.resources[r] -= n;
    return { stolen: {}, burned: b };
  }
  their.sabotage.walls_until = now + rules.walls_hours * 3600;
  their.sabotage.walls_cut = rules.walls_cut;
  return { stolen: {}, burned: {} };
}
