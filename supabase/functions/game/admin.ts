// The game owner's tools: start and stop timed events whenever they like, and
// give players resources and soldiers. Only accounts in the `admins` table
// (set by hand in the database, never from the game) may use them, and every
// use is written to the admin log. Nothing here can be bought.

import type { CastleState } from "../../../server/rules/castle_state.ts";
import { activeEvents, type EventOverride, type EventRules } from "../../../server/rules/events.ts";

/** The most of one resource or one kind of soldier a single gift may hold. */
export const GIFT_MAX = 1_000_000;
/** The longest run the owner may start, in hours. */
export const EVENT_MAX_HOURS = 24 * 14;
/** Owner runs older than this are forgotten. */
export const OVERRIDES_KEPT = 8 * 86400;

export const NOT_ADMIN = "Only the game owner can do that.";

/** What a gift holds: resources for the storage and soldiers for the garrison. */
export interface Gift {
  resources: Record<string, number>;
  troops: Record<string, number>;
}

/** An entry in the admin log. */
export interface AdminLogEntry {
  at: number;
  action: string;
  details: Record<string, unknown>;
}

/**
 * The owner run that starting event `id` at `t` adds, or why not. `hours`
 * defaults to the event's usual length.
 */
export function startEvent(rules: EventRules, id: unknown, hours: unknown, t: number): EventOverride | string {
  const e = rules.weekly.find((w) => w.id === id);
  if (e === undefined) return "There's no such event.";
  if (activeEvents(rules, t).some((a) => a.id === e.id)) return `${e.name} is already on.`;
  const h = hours === undefined || hours === null ? e.hours : hours;
  if (typeof h !== "number" || !Number.isFinite(h) || h <= 0 || h > EVENT_MAX_HOURS) {
    return `Choose between 1 and ${EVENT_MAX_HOURS} hours.`;
  }
  return { event: e.id, start: t, end: t + h * 3600 };
}

/** The override that ends event `id`'s current run at `t`, or why not. */
export function stopEvent(rules: EventRules, id: unknown, t: number): EventOverride | string {
  const e = rules.weekly.find((w) => w.id === id);
  if (e === undefined) return "There's no such event.";
  const on = activeEvents(rules, t).find((a) => a.id === e.id);
  if (on === undefined) return `${e.name} isn't on.`;
  return { event: e.id, start: on.start, end: t };
}

/** The gift asked for in an order, or why it can't be sent. */
export function checkGift(
  resourceNames: string[], hasUnit: (unit: string) => boolean, resources: unknown, troops: unknown,
): Gift | string {
  const gift: Gift = { resources: {}, troops: {} };
  const read = (given: unknown, known: (k: string) => boolean, into: Record<string, number>, what: string): string => {
    if (given === undefined || given === null) return "";
    if (typeof given !== "object" || Array.isArray(given)) return `Bad ${what}.`;
    for (const [k, n] of Object.entries(given as Record<string, unknown>)) {
      if (!known(k)) return `Unknown ${what === "soldiers" ? "unit" : "resource"}: ${k}.`;
      if (typeof n !== "number" || !Number.isInteger(n) || n < 0 || n > GIFT_MAX) {
        return `Give between 0 and ${GIFT_MAX} of each.`;
      }
      if (n > 0) into[k] = n;
    }
    return "";
  };
  const why = read(resources, (r) => resourceNames.includes(r), gift.resources, "resources") ||
    read(troops, hasUnit, gift.troops, "soldiers");
  if (why !== "") return why;
  if (Object.keys(gift.resources).length === 0 && Object.keys(gift.troops).length === 0) return "Choose something to give.";
  return gift;
}

/** Puts a gift in a castle. Owner gifts may go over the storage limit. */
export function giveCastle(castle: CastleState, gift: Gift): void {
  for (const [r, n] of Object.entries(gift.resources)) castle.resources[r] = (castle.resources[r] ?? 0) + n;
  for (const [unit, n] of Object.entries(gift.troops)) castle.troops[unit] = (castle.troops[unit] ?? 0) + n;
}

/** The report a player finds after a gift. */
export function giftReport(gift: Gift, t: number) {
  return { kind: "gift", at: t, resources: gift.resources, troops: gift.troops };
}

/** The owner's view of the calendar: every event, whether it's on, and when it ends or next starts. */
export function adminEvents(rules: EventRules, t: number) {
  const on = activeEvents(rules, t);
  return rules.weekly.map((e) => {
    const run = on.find((a) => a.id === e.id);
    return { id: e.id, name: e.name, hours: e.hours, on: run !== undefined, start: run?.start ?? 0, end: run?.end ?? 0 };
  });
}
