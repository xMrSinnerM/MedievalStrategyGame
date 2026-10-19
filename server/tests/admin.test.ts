// The game owner's tools (supabase/functions/game/admin.ts) and the owner's
// changes to the event calendar (server/rules/events.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { activeEvents, effectAt, lastInvasion, withOverrides, type EventRules } from "../rules/events.ts";
import { newPlayer, type World } from "../../supabase/functions/game/game.ts";
import { invade } from "../../supabase/functions/game/invasion.ts";
import { adminEvents, checkGift, giveCastle, startEvent, stopEvent } from "../../supabase/functions/game/admin.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const events: EventRules = json("data/events.json");
const utc = (s: string) => Date.parse(s) / 1000;
// 2026-10-12 is a Monday: no event is on.
const MONDAY = utc("2026-10-12T10:00:00Z");
// The invasion runs from Wednesday 2026-10-14 12:00 until Friday 12:00 UTC.
const INVASION = utc("2026-10-14T12:00:00Z");

test("the owner can start an event at any time, for its usual length or a chosen one", () => {
  assert.deepEqual(activeEvents(events, MONDAY), []);
  const run = startEvent(events, "plunder_weekend", undefined, MONDAY);
  assert.deepEqual(run, { event: "plunder_weekend", start: MONDAY, end: MONDAY + 54 * 3600 });
  const cal = withOverrides(events, [run as never]);
  assert.deepEqual(activeEvents(cal, MONDAY + 60).map((e) => e.id), ["plunder_weekend"]);
  assert.equal(effectAt(cal, MONDAY + 60, "baron_loot"), 1.5);
  assert.equal(effectAt(cal, MONDAY + 54 * 3600 + 1, "baron_loot"), 1, "over after its hours");
  const short = startEvent(events, "baron_invasion", 2, MONDAY);
  assert.deepEqual(short, { event: "baron_invasion", start: MONDAY, end: MONDAY + 7200 });
  assert.equal(startEvent(cal, "plunder_weekend", 5, MONDAY + 60), "Plunder Weekend is already on.");
  assert.equal(startEvent(events, "dragons", 5, MONDAY), "There's no such event.");
  assert.match(startEvent(events, "plunder_weekend", 0, MONDAY) as string, /Choose between/);
  assert.match(startEvent(events, "plunder_weekend", 10_000, MONDAY) as string, /Choose between/);
});

test("the owner can stop an event early, a scheduled run or their own", () => {
  const stop = stopEvent(events, "baron_invasion", INVASION + 3600);
  assert.deepEqual(stop, { event: "baron_invasion", start: INVASION, end: INVASION + 3600 });
  const cal = withOverrides(events, [stop as never]);
  assert.deepEqual(activeEvents(cal, INVASION + 3601), [], "stopped");
  assert.equal(lastInvasion(cal, INVASION + 3601)!.start, INVASION, "its rewards can still be claimed");
  assert.equal(stopEvent(cal, "baron_invasion", INVASION + 3601), "Baron Invasion isn't on.");
  // The next week's run comes as usual.
  assert.equal(activeEvents(cal, INVASION + 7 * 86400 + 60)[0].start, INVASION + 7 * 86400);
  // Started again after stopping: a new run.
  const again = startEvent(cal, "baron_invasion", 1, INVASION + 7200) as { start: number; end: number; event: string };
  const cal2 = withOverrides(events, [stop as never, again]);
  assert.equal(activeEvents(cal2, INVASION + 7300)[0].start, INVASION + 7200);
  const own = stopEvent(cal2, "baron_invasion", INVASION + 8000);
  assert.deepEqual(own, { event: "baron_invasion", start: INVASION + 7200, end: INVASION + 8000 });
});

test("an invasion the owner starts brings invader camps, and they leave when it's stopped", () => {
  const p = newPlayer(rules, world, "Valentin", MONDAY - 60);
  const run = startEvent(events, "baron_invasion", 3, MONDAY) as { event: string; start: number; end: number };
  const cal = withOverrides(events, [run]);
  const q = invade(p, cal, world, MONDAY + 10);
  assert.equal(q.camps.filter((c) => c.event === MONDAY).length, 3);
  assert.equal(q.event_key, MONDAY);
  assert.equal(lastInvasion(cal, MONDAY + 10)!.start, MONDAY);
  const stopped = withOverrides(events, [{ ...run, end: MONDAY + 600 }]);
  const r = invade(q, stopped, world, MONDAY + 601);
  assert.equal(r.camps.filter((c) => c.event !== undefined).length, 0);
  assert.equal(r.event_key, MONDAY, "points are kept for the rewards");
});

test("the owner's panel lists every event and whether it's on", () => {
  const cal = withOverrides(events, [startEvent(events, "plunder_weekend", 1, MONDAY) as never]);
  const view = adminEvents(cal, MONDAY + 60);
  assert.deepEqual(view.map((e) => [e.id, e.on]), [["plunder_weekend", true], ["baron_invasion", false]]);
  assert.equal(view[0].end, MONDAY + 3600);
});

test("gifts hold known resources and soldiers in sensible amounts", () => {
  const has = (u: string) => rules.buildings.hasUnit(u);
  const names = rules.buildings.resources;
  assert.deepEqual(checkGift(names, has, { gold: 500, wood: 0 }, { spearman: 10 }),
    { resources: { gold: 500 }, troops: { spearman: 10 } });
  assert.equal(checkGift(names, has, {}, {}), "Choose something to give.");
  assert.equal(checkGift(names, has, { diamonds: 5 }, {}), "Unknown resource: diamonds.");
  assert.equal(checkGift(names, has, {}, { dragon: 1 }), "Unknown unit: dragon.");
  assert.match(checkGift(names, has, { gold: -5 }, {}) as string, /Give between/);
  assert.match(checkGift(names, has, { gold: 1.5 }, {}) as string, /Give between/);
  assert.match(checkGift(names, has, { gold: 2_000_000 }, {}) as string, /Give between/);
  assert.equal(checkGift(names, has, "lots", {}), "Bad resources.");
});

test("a gift goes into the castle, even past the storage limit", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", 0);
  const cap = castle.storageCapacity();
  const before = castle.resources.gold;
  giveCastle(castle, { resources: { gold: cap * 3 }, troops: { archer: 7 } });
  assert.equal(castle.resources.gold, before + cap * 3);
  assert.equal(castle.troops.archer, 7);
  castle.advanceTo(3600);
  assert.ok(castle.resources.gold >= before + cap * 3, "production doesn't throw it away");
});
