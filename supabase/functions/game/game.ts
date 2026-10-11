// What the game server does with one player's request, without the
// database: create a new player, or run their world up to now and carry out
// an order. index.ts loads and saves the player and calls in here.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import { CastleState, type CastleData } from "../../../server/rules/castle_state.ts";
import type { Rules } from "../../../server/rules/load.ts";
import { advanceMarches, sendAttack, type Army, type March, type Report } from "../../../server/rules/marches.ts";

/** A player as stored in the players table (the game columns). */
export interface PlayerState {
  name: string;
  home_x: number;
  home_y: number;
  castle: CastleData;
  camps: CampData[];
  marches: March[];
  next_march: number;
}

export interface World {
  home: [number, number];
  camps: { id: string; name: string; position: [number, number]; level: number }[];
}

// deno-lint-ignore no-explicit-any
export type Request = Record<string, any>;

export interface Outcome {
  state: PlayerState;
  reports: Report[];
  error: string;
  /** Extra answer for the order, such as the id of a new building. */
  result?: unknown;
}

export const NAME_RULE = /^[\p{L}\p{N}][\p{L}\p{N} _'-]{1,18}[\p{L}\p{N}]$/u;

export function checkName(name: unknown): string {
  if (typeof name !== "string") return "Choose a name.";
  const trimmed = name.trim();
  if (trimmed.length < 3 || trimmed.length > 20) return "Names are 3 to 20 characters long.";
  if (!NAME_RULE.test(trimmed)) return "Use letters, numbers, spaces, ' _ and - only.";
  return "";
}

export function newPlayer(rules: Rules, world: World, name: string, now: number): PlayerState {
  const castle = CastleState.createNew(rules.buildings, "player_castle", `${name.trim()}'s Castle`, "player", now);
  return {
    name: name.trim(),
    home_x: world.home[0],
    home_y: world.home[1],
    castle: castle.toDict(),
    camps: world.camps.map((c) => ({ id: c.id, name: c.name, position: [c.position[0], c.position[1]], level: c.level, defeats: 0, rebuilt_at: 0 })),
    marches: [],
    next_march: 1,
  };
}

/** Brings the player's world up to `now`, then carries out the order (if any). */
export function act(rules: Rules, stored: PlayerState, req: Request, now: number): Outcome {
  const army: Army = {
    castle: CastleState.fromDict(rules.buildings, stored.castle),
    camps: structuredClone(stored.camps),
    marches: structuredClone(stored.marches),
    nextMarch: stored.next_march,
    home: [stored.home_x, stored.home_y],
  };
  const reports = advanceMarches(army, rules.barons, now);
  const castle = army.castle;
  castle.advanceTo(now);
  let error = "";
  let result: unknown = undefined;
  switch (req.action) {
    case "state":
      break;
    case "place": {
      if (!isCell(req.cell)) {
        error = "Bad cell.";
        break;
      }
      error = castle.checkPlace(String(req.type), req.cell);
      if (error === "") result = castle.place(String(req.type), req.cell, now);
      break;
    }
    case "upgrade":
      error = castle.checkUpgrade(Number(req.id));
      if (error === "") castle.upgrade(Number(req.id), now);
      break;
    case "cancel":
      if (!castle.cancel(Number(req.id), now)) error = "Nothing is being built there.";
      break;
    case "move":
      if (!isCell(req.cell) || !castle.move(Number(req.id), req.cell)) error = "There's no room there";
      break;
    case "recruit":
      error = castle.checkRecruit(String(req.unit), Number(req.amount));
      if (error === "") castle.recruit(String(req.unit), Number(req.amount), now);
      break;
    case "cancel_training":
      if (!castle.cancelTraining(Number(req.index), now)) error = "No such batch.";
      break;
    case "attack": {
      const sent = isArmy(req.army) ? req.army : null;
      error = sent === null ? "Bad army." : sendAttack(army, rules.barons, String(req.camp), sent, now);
      break;
    }
    default:
      error = "Unknown order.";
  }
  return {
    state: {
      ...stored,
      castle: castle.toDict(),
      camps: army.camps,
      marches: army.marches,
      next_march: army.nextMarch,
    },
    reports,
    error,
    result,
  };
}

function isCell(cell: unknown): cell is [number, number] {
  return Array.isArray(cell) && cell.length === 2 && cell.every((v) => Number.isInteger(v));
}

function isArmy(army: unknown): army is Record<string, number> {
  return army !== null && typeof army === "object" && !Array.isArray(army) &&
    Object.values(army as object).every((v) => typeof v === "number");
}
