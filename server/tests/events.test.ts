// Timed events (server/rules/events.ts) and the weekend loot bonus.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { activeEvents, effectAt, eventsView, upcomingEvents, type EventRules } from "../rules/events.ts";
import { makeRules } from "../rules/load.ts";
import { attackCamp, type CampData } from "../rules/baron_camp.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const events: EventRules = { weekly: [
  { id: "weekend", name: "Weekend", description: "", day: 5, hour: 18, hours: 54, effects: { baron_loot: 1.5 } },
  { id: "monday", name: "Monday", description: "", day: 1, hour: 0, hours: 2, effects: { baron_loot: 2 } },
] };
const utc = (s: string) => Date.parse(s) / 1000;

test("weekly events start and end on the right days, in UTC", () => {
  // 2026-10-09 is a Friday.
  assert.deepEqual(activeEvents(events, utc("2026-10-09T17:59:59Z")), []);
  const on = activeEvents(events, utc("2026-10-09T18:00:00Z"));
  assert.equal(on.length, 1);
  assert.equal(on[0].start, utc("2026-10-09T18:00:00Z"));
  assert.equal(on[0].end, utc("2026-10-12T00:00:00Z"));
  assert.equal(activeEvents(events, utc("2026-10-11T23:59:59Z"))[0].id, "weekend");
  // Monday midnight: the weekend has just ended and Monday's event begins.
  assert.deepEqual(activeEvents(events, utc("2026-10-12T00:00:00Z")).map((e) => e.id), ["monday"]);
  assert.deepEqual(activeEvents(events, utc("2026-10-12T02:00:00Z")), []);
});

test("upcoming events and effects", () => {
  const next = upcomingEvents(events, utc("2026-10-10T12:00:00Z"));
  assert.deepEqual(next.map((e) => e.id), ["monday", "weekend"]);
  assert.equal(next[0].start, utc("2026-10-12T00:00:00Z"));
  assert.equal(next[1].start, utc("2026-10-16T18:00:00Z"));
  assert.equal(effectAt(events, utc("2026-10-10T12:00:00Z"), "baron_loot"), 1.5);
  assert.equal(effectAt(events, utc("2026-10-14T12:00:00Z"), "baron_loot"), 1);
  assert.equal(effectAt(events, utc("2026-10-10T12:00:00Z"), "other"), 1);
  const view = eventsView(events, utc("2026-10-10T12:00:00Z"));
  assert.equal(view.active.length, 1);
  assert.equal(view.upcoming.length, 2);
});

test("the game's own calendar is valid", () => {
  const data: EventRules = json("data/events.json");
  assert.ok(data.weekly.length > 0);
  for (const e of data.weekly) {
    assert.ok(e.day >= 1 && e.day <= 7 && e.hour >= 0 && e.hour < 24 && e.hours > 0 && e.hours <= 168, e.id);
  }
});

test("a camp beaten during the bonus drops more loot", () => {
  const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
  const camp = (): CampData => ({ id: "c", name: "C", position: [0, 0], level: 1, defeats: 0, rebuilt_at: 0 });
  const army = { spearman: 200 };
  const plain = attackCamp(camp(), rules.barons, rules.buildings, army, 1, utc("2026-10-14T12:00:00Z"));
  rules.barons.lootFactor = (t) => effectAt(events, t, "baron_loot");
  const quiet = attackCamp(camp(), rules.barons, rules.buildings, army, 1, utc("2026-10-14T12:00:00Z"));
  const bonus = attackCamp(camp(), rules.barons, rules.buildings, army, 1, utc("2026-10-10T12:00:00Z"));
  assert.equal(plain.winner, "a");
  assert.deepEqual(quiet.loot, plain.loot);
  for (const r of Object.keys(plain.loot)) assert.equal(bonus.loot[r], Math.floor(rules.barons.loot(1)[r] * 1.5), r);
});
