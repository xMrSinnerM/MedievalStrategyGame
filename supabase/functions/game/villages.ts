// Resource villages online: who holds each one is a row of the villages
// table, shared by every player. act() (game.ts) checks and sends an army
// against a village ("attack_village") or soldiers to guard your own
// ("station"); index.ts stores them as raids rows with `village` set and
// resolves them here when they arrive, whoever's request comes first. Every
// request also collects what your villages made since the last one.

import { godotHash, type Dict } from "../../../server/rules/util.ts";
import type { Side, SiegeResult } from "../../../server/rules/battle.ts";
import type { Lead } from "../../../server/rules/gear.ts";
import type { Rules } from "../../../server/rules/load.ts";
import { capture, type VillageInfo, type VillageRules, type VillageState } from "../../../server/rules/villages.ts";
import type { CastleState } from "../../../server/rules/castle_state.ts";
import type { Raid } from "./game.ts";

/** A village an order is aimed at, as index.ts found it. */
export interface VillageTarget {
  info: VillageInfo;
  state: VillageState;
  /** Its owner is in the same alliance as the player giving the order. */
  ally: boolean;
  /** How many villages that player holds now. */
  held: number;
}

/** What happened at a village, as each side's report shows it. */
export interface VillageReport {
  kind: "village";
  role: "attacker" | "defender";
  raid: number;
  village: string;
  /** The village's name. */
  name: string;
  resource: string;
  level: number;
  /** The other side: the owner the attacker found there ("" for the militia), or the attacker. */
  other: string;
  at: number;
  /**
   * fought: there was a battle. peace: the village had just changed hands,
   * so the army turned back. joined: the village was already the attacker's,
   * so the army stayed to guard it. lost: soldiers sent to guard a village
   * found it taken, and turned back.
   */
  result: "fought" | "peace" | "joined" | "lost";
  winner?: "a" | "b";
  a?: Side;
  b?: Side;
  walls?: SiegeResult["walls"];
  courtyard?: SiegeResult["courtyard"];
  tools?: SiegeResult["tools"];
  spoils: Dict;
  /** The village changed hands. */
  captured: boolean;
  /** The attackers won but their keep had no room for another village. */
  no_room?: boolean;
  /** Attacker's report: their commander and the xp earned (given when the army is home). */
  lead?: { id: number; name: string; xp: number };
}

export interface VillageOutcome {
  state: VillageState;
  /** The report for whoever sent the army (none when guards simply arrive). */
  attackerReport: VillageReport | null;
  /** The report for the village's owner before the battle, if anyone held it. */
  ownerReport: VillageReport | null;
  /** The army walking home, with what it carries (empty when it stays as the guard). */
  survivors: Dict;
  loot: Dict;
  /** The old owner's guards left standing when the village was taken, walking home. */
  guardHome: Dict;
  /** The attackers' commander with the xp earned. */
  lead?: Lead;
}

/** Why this village can't be attacked by `me` now ("" if it can). */
export function checkVillageAttack(rules: VillageRules, castle: CastleState, me: string, v: VillageTarget, now: number): string {
  if (v.state.owner === me) return "This village is already yours.";
  if (v.ally) return "This village belongs to your alliance.";
  if (now < rules.peaceUntil(v.state)) return "This village just changed hands and is at peace for now.";
  return rules.checkRoom(castle.keepLevel(), v.held);
}

function add(to: Dict, more: Dict): Dict {
  const out = { ...to };
  for (const unit of Object.keys(more)) if (more[unit] > 0) out[unit] = (out[unit] ?? 0) + more[unit];
  return out;
}

/**
 * An army reaches a village. Guards sent by its owner join the soldiers
 * there. Attackers fight whoever holds it, unless it is at peace or already
 * theirs; a win carries off what the village holds and, if `room` (the
 * attacker's keep can hold one more village), takes it over. Whoever held it
 * keeps the guards that are left after a defeat of the attackers.
 */
export function resolveVillageRaid(rules: Rules, info: VillageInfo, state: VillageState, raid: Raid, room: boolean): VillageOutcome {
  const at = raid.arrive;
  const base = {
    kind: "village" as const, raid: raid.id, village: info.id, name: info.name, resource: info.resource, level: info.level,
    at, spoils: {}, captured: false,
  };
  const none = { state, ownerReport: null, survivors: {}, loot: {}, guardHome: {} };
  if (raid.mission === "station") {
    if (state.owner === raid.attacker_name) return { ...none, state: { ...state, guard: add(state.guard, raid.army) }, attackerReport: null };
    return { ...none, survivors: raid.army,
      attackerReport: { ...base, role: "attacker", other: state.owner, result: "lost" } };
  }
  if (state.owner === raid.attacker_name) {
    return { ...none, state: { ...state, guard: add(state.guard, raid.army) },
      attackerReport: { ...base, role: "attacker", other: "", result: "joined" } };
  }
  if (at < rules.villages.peaceUntil(state)) {
    return { ...none, survivors: raid.army, attackerReport: { ...base, role: "attacker", other: state.owner, result: "peace" } };
  }
  const seed = raid.id * 7919 + godotHash(info.id);
  const f = rules.villages.attack(rules.buildings, rules.barons, info, state, raid.army, seed, at, raid.waves, raid.tools ?? {},
    raid.lead?.fx ?? {});
  const won = f.winner === "a";
  const held = state.owner !== "";
  let next: VillageState = state;
  let guardHome: Dict = {};
  if (won && room) {
    next = capture(state, raid.attacker_name, at);
    if (held) guardHome = f.guardLeft;
  } else if (held) {
    // The owner keeps the village with what is left of its guard; a win carried off its store.
    next = { ...state, guard: f.guardLeft, paid_at: won ? at : state.paid_at };
  }
  const gear = rules.gear;
  const lead = raid.lead
    ? { ...raid.lead, xp: won ? (held ? gear.xpPlayerWin : gear.xpWinPerLevel * info.level) : gear.xpLoss }
    : undefined;
  const fight = {
    ...base, result: "fought" as const, winner: f.winner, a: f.a, b: f.b, walls: f.walls, courtyard: f.courtyard,
    ...(f.tools ? { tools: f.tools } : {}), spoils: f.loot, captured: won && room, ...(won && !room ? { no_room: true } : {}),
  };
  return {
    state: next,
    attackerReport: { ...fight, role: "attacker", other: state.owner,
      ...(lead ? { lead: { id: lead.id, name: lead.name, xp: lead.xp } } : {}) },
    ownerReport: held ? { ...fight, role: "defender", other: raid.attacker_name } : null,
    survivors: f.survivors,
    loot: f.loot,
    guardHome,
    ...(lead ? { lead } : {}),
  };
}
