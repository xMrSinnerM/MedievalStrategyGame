// Treasure chests and the Wheel of Fortune. Chests come as rewards (the
// coffer, the Royal Gift, achievements, seasons); opening one spins its wheel
// of eight prizes, picked by weight. The spin is decided by the castle and how
// many chests it has opened, so the game shows the wheel landing where the
// server does. A port of scripts/economy/chest_rules.gd; the numbers are in
// data/chests.json.

import type { CastleState } from "./castle_state.ts";
import { give, type Reward } from "./quests.ts";
import { Rng } from "./rng.ts";
import { clamp, godotHash, round, type Dict } from "./util.ts";

const ORDER = ["wooden", "iron", "golden"];

export interface ChestRules {
  scale: number[];
  kinds: Record<string, { name: string; color: string; wheel: { weight: number; reward: Reward; jackpot?: boolean }[] }>;
}

/** What a wheel slot gives, for this keep level. */
export function slotReward(rules: ChestRules, kind: string, index: number, keep: number): Reward {
  const mult = rules.scale[clamp(keep, 1, rules.scale.length) - 1];
  const base = rules.kinds[kind].wheel[index].reward;
  const out: Reward = {};
  if (base.resources) {
    const resources: Dict = {};
    for (const [r, n] of Object.entries(base.resources)) resources[r] = round(n * mult);
    out.resources = resources;
  }
  if (base.troops) out.troops = { ...base.troops };
  if (base.tools) out.tools = { ...base.tools };
  if (base.chests) out.chests = { ...base.chests };
  return out;
}

/** The wheel slot the next chest of this kind lands on. */
export function spin(castle: CastleState, rules: ChestRules, kind: string): number {
  const wheel = rules.kinds[kind].wheel;
  const sum = wheel.reduce((s, w) => s + w.weight, 0);
  const rng = new Rng(castle.chests.opened * 1000003 + godotHash(castle.castleName) + ORDER.indexOf(kind) * 7919);
  let roll = rng.randi() % sum;
  for (let i = 0; i < wheel.length; i++) {
    roll -= wheel[i].weight;
    if (roll < 0) return i;
  }
  return wheel.length - 1;
}

export function checkOpen(castle: CastleState, rules: ChestRules, kind: unknown): string {
  if (typeof kind !== "string" || !Object.hasOwn(rules.kinds, kind)) return "There's no such chest.";
  if ((castle.chests.have[kind] ?? 0) <= 0) return `You have no ${rules.kinds[kind].name.toLowerCase()}.`;
  return "";
}

/** Opens a chest: the error, or "" with the slot it landed on and what it gave. */
export function openChest(castle: CastleState, rules: ChestRules, kind: unknown): { error: string; slot?: number; reward?: Reward } {
  const why = checkOpen(castle, rules, kind);
  if (why !== "") return { error: why };
  const k = kind as string;
  const slot = spin(castle, rules, k);
  const reward = slotReward(rules, k, slot, castle.keepLevel());
  castle.chests.have[k] -= 1;
  if (castle.chests.have[k] <= 0) delete castle.chests.have[k];
  castle.chests.opened += 1;
  give(castle, reward);
  return { error: "", slot, reward };
}
