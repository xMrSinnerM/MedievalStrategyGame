// Baron Invasions (supabase/functions/game/invasion.ts): invader camps that
// come and go with the event, rise a level with every win and give event points.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import type { EventRules } from "../rules/events.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";
import { invade } from "../../supabase/functions/game/invasion.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const events: EventRules = json("data/events.json");
const utc = (s: string) => Date.parse(s) / 1000;
// 2026-10-14 is a Wednesday: the invasion runs from 12:00 until Friday 12:00 UTC.
const START = utc("2026-10-14T12:00:00Z");
const END = START + 48 * 3600;
const ctx = { events: { rules: events, world } };

function player(t: number, troops: Record<string, number> = {}): PlayerState {
  const p = newPlayer(rules, world, "Valentin", t);
  p.castle.troops = troops;
  return p;
}

test("world.json has places for invader camps around nearly every castle spot", () => {
  assert.equal(world.invasion_spots?.length, world.spots.length);
  const enough = world.invasion_spots!.filter((r) => r.length >= 3).length;
  assert.ok(enough >= world.spots.length * 0.9, `${enough} of ${world.spots.length}`);
});

test("invader camps appear when the invasion starts and points start from 0", () => {
  const p = player(START - 3600);
  assert.equal(invade(p, events, world, START - 1), p, "nothing before the event");
  const q = invade({ ...p, event_points: 99, event_key: 5 }, events, world, START + 60);
  const invaders = q.camps.filter((c) => c.event !== undefined);
  assert.equal(invaders.length, 3);
  assert.deepEqual(invaders.map((c) => c.level), [1, 2, 3], "keep level 1: levels 1, 2 and 3");
  assert.deepEqual(invaders.map((c) => c.position), world.invasion_spots![0].slice(0, 3));
  assert.ok(invaders.every((c) => c.event === START && c.points === 10 && c.rebuild === 120));
  assert.equal(q.event_key, START);
  assert.equal(q.event_points, 0);
  assert.equal(q.camps.length, world.camps.length + 3);
  // Asking again changes nothing.
  assert.equal(invade(q, events, world, START + 120), q);
});

test("bigger keeps meet stronger invaders", () => {
  const p = player(START - 3600);
  p.castle.buildings.find((b) => b.type === "keep")!.level = 3;
  const q = invade(p, events, world, START);
  assert.deepEqual(q.camps.filter((c) => c.event).map((c) => c.level), [5, 6, 7]);
});

test("winning raises an invader camp a level and earns points; the camps leave after the event", () => {
  let p = player(START - 3600, { swordsman: 200 });
  let out = act(rules, p, { action: "state" }, START + 10, ctx);
  const camp = out.state.camps.find((c) => c.event !== undefined)!;
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { swordsman: 200 } }, START + 20, ctx);
  assert.equal(out.error, "");
  const march = out.state.marches[0];
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx);
  const report = out.reports[0];
  assert.equal(report.winner, "a");
  assert.equal(report.points, 10, "10 points per level of a level 1 camp");
  assert.equal(report.leveled, true, "one win is enough to rise a level");
  assert.equal(out.state.event_points, 10);
  assert.equal(out.state.barons_beaten, 1);
  const after = out.state.camps.find((c) => c.id === camp.id)!;
  assert.equal(after.level, 2);
  assert.equal(after.rebuilt_at, march.arrive + 120, "invaders rebuild quickly");
  // While the army marches home after the event ends, its camp stays.
  out = act(rules, out.state, { action: "state" }, Math.min(march.back - 1, END + 1), ctx);
  p = out.state;
  if (march.back - 1 >= END) assert.ok(p.camps.some((c) => c.id === camp.id));
  out = act(rules, p, { action: "state" }, END + 1, ctx);
  out = act(rules, out.state, { action: "state" }, END + 2, ctx);
  assert.equal(out.state.camps.filter((c) => c.event !== undefined).length, 0, "gone once the event is over");
  assert.equal(out.state.camps.length, world.camps.length);
  assert.equal(out.state.event_points, 10, "points are kept until the next invasion");
});

test("a castle on a spot with no places gets no invaders, and other camps are never touched", () => {
  const p = { ...player(START - 3600), home_x: 1, home_y: 1 };
  const q = invade(p, events, world, START);
  assert.equal(q.camps.length, world.camps.length);
  assert.equal(q.event_key, START);
});
