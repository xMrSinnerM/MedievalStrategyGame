// Baron Invasions (a timed event, see data/events.json): while one runs,
// every castle gets a few invader camps nearby, which rise a level with every
// win and give event points. They are ordinary camps in the player's camp
// list with an `event` field, so marches and battles treat them like any
// other; this file only adds and removes them.

import type { CampData } from "../../../server/rules/baron_camp.ts";
import { activeEvents, type EventRules } from "../../../server/rules/events.ts";
import type { Report } from "../../../server/rules/marches.ts";
import type { PlayerState, World } from "./game.ts";

/**
 * The player's camps and event points as of `t`: when an invasion has begun
 * since they last played, its camps appear (on the spots world.json lists
 * around their castle) and their event points start again from 0. Invader
 * camps of an invasion that is over leave once no army is marching to or
 * from them. `offset` runs the event calendar that many seconds ahead
 * (local testing); invasions are still keyed by their start on the real clock.
 */
export function invade(stored: PlayerState, events: EventRules, world: World, t: number, offset = 0): PlayerState {
  const on = activeEvents(events, t + offset).find((e) => e.invasion !== undefined);
  const start = on === undefined ? undefined : on.start - offset;
  const busy = new Set(stored.marches.map((m) => m.camp));
  const camps = stored.camps.filter((c) => c.event === undefined || c.event === start || busy.has(c.id));
  let eventKey = stored.event_key ?? 0;
  let eventPoints = stored.event_points ?? 0;
  if (on !== undefined && on.invasion !== undefined && start !== undefined && eventKey !== start) {
    eventKey = start;
    eventPoints = 0;
    const inv = on.invasion;
    const spot = (world.spots ?? []).findIndex(([x, y]) => x === stored.home_x && y === stored.home_y);
    const places = spot < 0 ? [] : world.invasion_spots?.[spot] ?? [];
    const keep = stored.castle.buildings.find((b) => b.type === "keep")?.level ?? 1;
    const first = 1 + inv.level_per_keep * (keep - 1);
    for (let i = 0; i < Math.min(inv.camps, places.length); i++) {
      camps.push({
        id: `invader_${start}_${i}`,
        name: inv.names[i % inv.names.length] ?? "Invaders' Camp",
        position: [places[i][0], places[i][1]],
        level: first + i,
        defeats: 0,
        rebuilt_at: 0,
        event: start,
        points: inv.points_per_level,
        rebuild: inv.rebuild,
      } satisfies CampData);
    }
  }
  if (camps.length === stored.camps.length && eventKey === stored.event_key && eventPoints === stored.event_points) return stored;
  return { ...stored, camps, event_key: eventKey, event_points: eventPoints };
}

/** Event points won in these battle reports for the invasion `eventKey`. */
export function eventPoints(reports: Report[], eventKey: number): number {
  let n = 0;
  for (const r of reports) if (r.event !== undefined && r.event === eventKey) n += r.points ?? 0;
  return n;
}
