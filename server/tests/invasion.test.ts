// Baron Invasions (supabase/functions/game/invasion.ts): invader camps that
// come and go with the event, rise a level with every win and give event points.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { lastInvasion, type EventRules } from "../rules/events.ts";
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
  assert.equal(q.camps.length, (world.camps.length + (world.fortresses?.length ?? 0)) + 3);
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
  assert.equal(out.state.camps.length, (world.camps.length + (world.fortresses?.length ?? 0)));
  assert.equal(out.state.event_points, 10, "points are kept until the next invasion");
});

test("a castle on a spot with no places gets no invaders, and other camps are never touched", () => {
  const p = { ...player(START - 3600), home_x: 1, home_y: 1 };
  const q = invade(p, events, world, START);
  assert.equal(q.camps.length, (world.camps.length + (world.fortresses?.length ?? 0)));
  assert.equal(q.event_key, START);
});

test("reward tiers are claimed in order once you have the points, and start again with the next invasion", () => {
  const tiers = events.weekly.find((e) => e.invasion)!.invasion!.rewards!;
  let p: PlayerState = { ...player(START - 3600), event_key: START, event_points: tiers[1].points, event_claimed: 0 };
  p.castle.resources = { wood: 100, stone: 100, food: 100, gold: 100 };
  let out = act(rules, p, { action: "claim_reward", tier: 1 }, START + 10, ctx);
  assert.equal(out.error, "Claim the rewards in order.");
  out = act(rules, p, { action: "claim_reward", tier: 0 }, START + 10, ctx);
  assert.equal(out.error, "");
  assert.equal(out.state.event_claimed, 1);
  assert.ok(out.state.castle.resources.wood >= 100 + tiers[0].resources!.wood - 1, "the resources arrive");
  out = act(rules, out.state, { action: "claim_reward", tier: 0 }, START + 11, ctx);
  assert.equal(out.error, "You already have that reward.");
  out = act(rules, out.state, { action: "claim_reward", tier: 1 }, START + 12, ctx);
  assert.equal(out.error, "");
  out = act(rules, out.state, { action: "claim_reward", tier: 2 }, START + 13, ctx);
  assert.equal(out.error, `That reward needs ${tiers[2].points} event points.`);
  out = act(rules, out.state, { action: "claim_reward", tier: 99 }, START + 13, ctx);
  assert.equal(out.error, "There's no such reward.");
  // Soldiers join the garrison.
  p = { ...out.state, event_points: tiers[2].points };
  out = act(rules, p, { action: "claim_reward", tier: 2 }, START + 14, ctx);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.troops.spearman, tiers[2].troops!.spearman);
  // Resources never overflow the storage.
  p = { ...out.state, event_points: tiers[3].points };
  p.castle.resources = { wood: 990, stone: 990, food: 990, gold: 990 };
  out = act(rules, p, { action: "claim_reward", tier: 3 }, START + 15, ctx);
  assert.equal(out.error, "");
  assert.ok(out.state.castle.resources.wood <= rules.buildings.storage("keep", 1));
  // A week later the next invasion starts afresh.
  out = act(rules, out.state, { action: "state" }, START + 7 * 86400 + 5, ctx);
  assert.equal(out.state.event_key, START + 7 * 86400);
  assert.equal(out.state.event_points, 0);
  assert.equal(out.state.event_claimed, 0);
});

test("the last invasion is the one on now, or else the one that ended most recently", () => {
  assert.equal(lastInvasion(events, START + 60)!.start, START);
  assert.equal(lastInvasion(events, END + 3 * 86400)!.start, START, "the weekend after");
  assert.equal(lastInvasion(events, START - 1)!.start, START - 7 * 86400);
});

test("points from an earlier invasion can't claim this one's rewards", () => {
  const p: PlayerState = { ...player(START - 3600), event_key: START - 7 * 86400, event_points: 5000, event_claimed: 0 };
  const out = act(rules, p, { action: "claim_reward", tier: 0 }, START - 60, { events: { rules: events, world } });
  assert.equal(out.error, "");
  const later = act(rules, p, { action: "claim_reward", tier: 0 }, START + 7 * 86400 - 60, { events: { rules: events, world } });
  assert.match(later.error, /needs \d+ event points/);
});
