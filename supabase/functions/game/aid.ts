// Helping allies: carts of resources and soldiers sent to defend another
// member's castle. act() (game.ts) checks and pays for a shipment; index.ts
// stores it in the aid table and resolves it on time: carts unload when they
// arrive, defenders stand in the ally's castle until they leave, fight beside
// its garrison if it is attacked meanwhile (fightRaid), then walk home.

import { advanceMarches, type Army, type Report } from "../../../server/rules/marches.ts";
import { CastleState } from "../../../server/rules/castle_state.ts";
import type { Rules } from "../../../server/rules/load.ts";
import type { Dict } from "../../../server/rules/util.ts";
import { scored, type PlayerState } from "./game.ts";

/** The numbers for helping allies, from data/aid.json. */
export interface AidRules {
  carry_per_keep_level: number;
  station_hours: number;
}

/** A shipment of resources ("resources") or soldiers ("troops") to an ally (a row of the aid table). */
export interface Aid {
  id: number;
  kind: "resources" | "troops";
  sender_name: string;
  receiver_name: string;
  resources: Dict;
  army: Dict;
  from: [number, number];
  to: [number, number];
  depart: number;
  /** When it reaches the ally. */
  arrive: number;
  /** Defenders: when they set off home (arrive for carts). */
  leave: number;
  /** Defenders: when they are home again (arrive for carts). */
  back: number;
}

/** What an ally gets told, or the sender, about a shipment (a server report). */
export interface AidReport {
  kind: "aid";
  /** received / delivered (carts), defended (your defenders fought off an attack, or fell). */
  event: "received" | "delivered" | "defended";
  /** The other player. */
  name: string;
  at: number;
  resources?: Dict;
  /** Resources the receiver's storage couldn't hold. */
  spilled?: Dict;
  /** defended: who attacked, whether the castle held, and the defenders lost. */
  attacker?: string;
  held?: boolean;
  lost?: Dict;
}

/** How much one cart shipment can carry from this castle. */
export function carryLimit(castle: CastleState, rules: AidRules): number {
  return rules.carry_per_keep_level * Math.max(1, castle.keepLevel());
}

/** Why these resources can't be sent ("" if they can). */
export function checkShipment(castle: CastleState, rules: AidRules, resources: unknown): string {
  if (resources === null || typeof resources !== "object" || Array.isArray(resources)) return "Choose what to send.";
  let total = 0;
  for (const [r, n] of Object.entries(resources as Record<string, unknown>)) {
    if (!(r in castle.resources)) return "Unknown resource.";
    if (typeof n !== "number" || !Number.isInteger(n) || n < 0) return "Choose what to send.";
    if (n > Math.floor(castle.resources[r])) return `You don't have that much ${r}.`;
    total += n;
  }
  if (total <= 0) return "Choose what to send.";
  const cap = carryLimit(castle, rules);
  if (total > cap) return `Your carts carry at most ${cap} at a time.`;
  return "";
}

export interface Delivery {
  /** The receiver, run up to the cart's arrival and with the resources unloaded. */
  receiver: PlayerState;
  /** Battles the receiver's own armies fought on the way (robber barons). */
  campReports: Report[];
  receiverReport: AidReport;
  senderReport: AidReport;
}

/** A cart reaches the ally's castle: what fits in their storage is unloaded, the rest is lost. */
export function deliver(rules: Rules, stored: PlayerState, aid: Aid): Delivery {
  const world: Army = {
    castle: CastleState.fromDict(rules.buildings, stored.castle),
    camps: structuredClone(stored.camps),
    marches: structuredClone(stored.marches),
    nextMarch: stored.next_march,
    home: [stored.home_x, stored.home_y],
  };
  const campReports = advanceMarches(world, rules.barons, aid.arrive);
  const castle = world.castle;
  castle.advanceTo(aid.arrive);
  const cap = castle.storageCapacity();
  const got: Dict = {};
  const spilled: Dict = {};
  for (const r of Object.keys(aid.resources)) {
    if (!(r in castle.resources) || aid.resources[r] <= 0) continue;
    const room = Math.max(0, Math.floor(cap - castle.resources[r]));
    got[r] = Math.min(room, aid.resources[r]);
    castle.resources[r] += got[r];
    if (got[r] < aid.resources[r]) spilled[r] = aid.resources[r] - got[r];
  }
  return {
    receiver: { ...stored, castle: castle.toDict(), camps: world.camps, marches: world.marches, next_march: world.nextMarch,
      ...scored(stored, campReports) },
    campReports,
    receiverReport: { kind: "aid", event: "received", name: aid.sender_name, at: aid.arrive, resources: got },
    senderReport: { kind: "aid", event: "delivered", name: aid.receiver_name, at: aid.arrive, resources: got, spilled },
  };
}

/** Whether these defenders stand in the ally's castle at time `t`. */
export function stationed(aid: Pick<Aid, "kind" | "arrive" | "leave">, t: number): boolean {
  return aid.kind === "troops" && aid.arrive <= t && t < aid.leave;
}

/**
 * Calling defenders home: on the road they turn round where they are; in
 * the ally's castle they leave now. Returns the new times, or why not.
 */
export function recall(aid: Pick<Aid, "depart" | "arrive" | "leave" | "back">, now: number):
  { arrive: number; leave: number; back: number } | string {
  if (now >= aid.leave) return "They're already on their way home.";
  if (now < aid.arrive) return { arrive: now, leave: now, back: now + (now - aid.depart) };
  return { arrive: aid.arrive, leave: now, back: now + (aid.arrive - aid.depart) };
}
