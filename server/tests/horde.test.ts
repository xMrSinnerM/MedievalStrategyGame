// The Ember Horde (supabase/functions/game/horde.ts): horde camps that come
// and go with the event, horde points and war trophies, the Trophy Market and
// the ranked prizes.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { activeEvents, eventsView, lastHorde, withOverrides, type EventRules, type HordeRules } from "../rules/events.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";
import { campsFor, hordeArrives, prizeFor } from "../../supabase/functions/game/horde.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  {}, {}, {}, json("data/fortresses.json"), json("data/horde.json"));
const world: World = json("server/world/world.json");
const events: EventRules = json("data/events.json");
const horde: HordeRules = events.weekly.find((e) => e.horde)!.horde!;
const utc = (s: string) => Date.parse(s) / 1000;
// 2026-10-26 is a Monday: the horde rides from 12:00 until Wednesday 12:00 UTC.
const START = utc("2026-10-26T12:00:00Z");
const END = START + 48 * 3600;
const WEEK = 7 * 86400;
const ctx = { events: { rules: events, world } };

function player(t: number, troops: Record<string, number> = {}): PlayerState {
  const p = newPlayer(rules, world, "Valentin", t);
  p.castle.troops = troops;
  return p;
}

const hordeCamps = (p: PlayerState) => p.camps.filter((c) => c.horde !== undefined);

test("the horde rides on Monday 12:00 UTC for two days and never meets the other events", () => {
  assert.deepEqual(activeEvents(events, START - 1).map((e) => e.id), []);
  assert.deepEqual(activeEvents(events, START + 60).map((e) => e.id), ["ember_horde"]);
  assert.deepEqual(activeEvents(events, END - 1).map((e) => e.id), ["ember_horde"]);
  assert.deepEqual(activeEvents(events, END).map((e) => e.id), ["baron_invasion"]);
  assert.equal(lastHorde(events, END + 3 * 86400)!.start, START, "the last horde until the next arrives");
  assert.equal(lastHorde(events, START + WEEK)!.start, START + WEEK);
  // Once it's over, the game is told about it, even when the owner stopped it early.
  const stopped = withOverrides(events, [{ event: "ember_horde", start: START, end: START + 3600 }]);
  const recent = eventsView(stopped, START + 7200).recent.find((e) => e.id === "ember_horde")!;
  assert.deepEqual([recent.start, recent.end], [START, START + 3600]);
  assert.equal(eventsView(events, START + 60).recent.some((e) => e.id === "ember_horde"), false, "not while it rides");
});

test("horde camps appear when the horde arrives, the Warlord's strongest, and the score starts again", () => {
  const p = { ...player(START - 3600), horde_key: 7, horde_points: 99, horde: { trophies: 50, bought: { coin: 1 }, ranked: true } };
  assert.equal(hordeArrives(p, events, world, START - 1), p, "nothing before the event");
  const q = hordeArrives(p, events, world, START + 60);
  const camps = hordeCamps(q);
  assert.equal(camps.length, 4);
  assert.deepEqual(camps.map((c) => c.level), [1, 2, 3, 6], "keep level 1: outriders at 1, 2 and 3, the Warlord at 6");
  assert.deepEqual(camps.map((c) => c.position), world.invasion_spots![0].slice(0, 4));
  assert.ok(camps.every((c) => c.horde === START && c.until === END && c.rebuild === horde.rebuild));
  assert.equal(camps[3].name, "The Warlord's Camp");
  assert.equal(camps[3].points, 30);
  assert.equal(q.horde_key, START);
  assert.equal(q.horde_points, 0);
  assert.deepEqual(q.horde, { trophies: 0, bought: {}, ranked: false });
  assert.equal(hordeArrives(q, events, world, START + 120), q, "asking again changes nothing");
});

test("with room for fewer camps the Warlord's comes first", () => {
  assert.deepEqual(campsFor(horde, 2).map((c) => c.name), ["The Warlord's Camp", "Ashrider Camp"]);
  assert.equal(campsFor(horde, 0).length, 0);
  const p = { ...player(START - 3600), home_x: 1, home_y: 1 };
  assert.equal(hordeCamps(hordeArrives(p, events, world, START)).length, 0, "no places, no horde camps");
});

test("horde camps field the horde's soldiers: more horsemen than the barons", () => {
  const camp = hordeCamps(hordeArrives(player(START - 1), events, world, START))[3];
  const garrison = rules.barons.forCamp(camp).garrison(camp.level);
  assert.ok((garrison.horseman ?? 0) > 0);
  assert.equal(rules.barons.forCamp({}), rules.barons);
});

test("a win raises the camp a level and earns horde points and war trophies; the camps leave after the event", () => {
  let out = act(rules, player(START - 3600, { swordsman: 300 }), { action: "state" }, START + 10, ctx);
  const camp = hordeCamps(out.state)[0];
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { swordsman: 300 } }, START + 20, ctx);
  assert.equal(out.error, "");
  const march = out.state.marches[0];
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx);
  const report = out.reports[0];
  assert.equal(report.winner, "a");
  assert.equal(report.horde, START);
  assert.equal(report.points, 10);
  assert.equal(report.trophies, 2);
  assert.equal(report.leveled, true);
  assert.equal(out.state.horde_points, 10);
  assert.equal(out.state.horde!.trophies, 2);
  assert.equal(out.state.event_points, 0, "Baron Invasion points are separate");
  const after = out.state.camps.find((c) => c.id === camp.id)!;
  assert.equal(after.level, 2);
  assert.equal(after.rebuilt_at, march.arrive + horde.rebuild);
  out = act(rules, out.state, { action: "state" }, Math.max(march.back, END) + 1, ctx);
  out = act(rules, out.state, { action: "state" }, Math.max(march.back, END) + 2, ctx);
  assert.equal(hordeCamps(out.state).length, 0, "gone once the event is over");
  assert.equal(out.state.horde_points, 10, "points are kept until the next horde");
});

test("a battle fought after the horde has gone earns nothing", () => {
  const p = hordeArrives(player(END - 60, { swordsman: 300 }), events, world, END - 60);
  let out = act(rules, p, { action: "state" }, END - 10, ctx);
  const camp = hordeCamps(out.state)[0];
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { swordsman: 300 } }, END - 5, ctx);
  const march = out.state.marches[0];
  assert.ok(march.arrive > END, "the army arrives after the end");
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx);
  assert.equal(out.reports[0].winner, "a");
  assert.equal(out.reports[0].points, 0);
  assert.equal(out.state.horde_points, 0);
  assert.equal(out.state.horde!.trophies, 0);
});

test("the Trophy Market sells for war trophies, in stock, while the horde is the last one", () => {
  const p = hordeArrives(player(START - 3600), events, world, START);
  p.castle.resources = { wood: 0, stone: 0, food: 0, gold: 0 };
  p.horde = { trophies: 200, bought: {}, ranked: false };
  let out = act(rules, p, { action: "buy_horde", item: "spears" }, START + 10, ctx);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.troops.spearman, 40);
  assert.equal(out.state.horde!.trophies, 140);
  assert.equal(out.state.horde!.bought.spears, 1);
  out = act(rules, out.state, { action: "buy_horde", item: "ladders" }, START + 11, ctx);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.tools.ladder, 10);
  out = act(rules, out.state, { action: "buy_horde", item: "standard" }, START + 12, ctx);
  assert.equal(out.error, "That costs 400 war trophies.");
  out = act(rules, out.state, { action: "buy_horde", item: "dragons" }, START + 12, ctx);
  assert.equal(out.error, "The market doesn't sell that.");
  // Resources must fit in the storage.
  out.state.castle.resources.wood = 1000;
  out = act(rules, { ...out.state, horde: { ...out.state.horde!, trophies: 1000 } }, { action: "buy_horde", item: "timber" }, START + 13, ctx);
  assert.match(out.error, /Make room in your storage/);
  // Gear goes in the bag.
  out = act(rules, out.state, { action: "buy_horde", item: "standard" }, START + 14, ctx);
  assert.equal(out.error, "");
  const bag = out.state.castle.armoury!.bag;
  assert.equal(bag[bag.length - 1].name, "Ember-Breaker Standard");
  out = act(rules, out.state, { action: "buy_horde", item: "standard" }, START + 15, ctx);
  assert.equal(out.error, "That's sold out until the next horde.");
  // Still open after the horde has gone, until the next one arrives; then it all starts again.
  out = act(rules, out.state, { action: "buy_horde", item: "spears" }, END + 86400, ctx);
  assert.equal(out.error, "");
  out = act(rules, out.state, { action: "state" }, START + WEEK + 1, ctx);
  assert.deepEqual(out.state.horde, { trophies: 0, bought: {}, ranked: false });
  // A player who never met the horde can't shop.
  out = act(rules, { ...player(START - 3600), horde_key: 0 }, { action: "buy_horde", item: "spears" }, START - 60,
    { events: { rules: events, world } });
  assert.equal(out.error, "The Trophy Market opens when the Ember Horde arrives.");
});

test("ranked prizes go by rank, once the horde has gone, one per player", () => {
  assert.equal(prizeFor(horde.prizes, 1)!.up_to, 1);
  assert.equal(prizeFor(horde.prizes, 2)!.up_to, 3);
  assert.equal(prizeFor(horde.prizes, 10)!.up_to, 10);
  assert.equal(prizeFor(horde.prizes, 26)!.up_to, 0, "everyone with points gets something");
  assert.equal(prizeFor(horde.prizes, 0), undefined);
  const p = hordeArrives(player(START - 3600), events, world, START);
  p.horde_points = 500;
  p.castle.resources = { wood: 0, stone: 0, food: 0, gold: 0 };
  let out = act(rules, p, { action: "claim_horde_prize" }, START + 60, { ...ctx, hordeRank: 1 });
  assert.equal(out.error, "The prizes are given once the horde has gone.");
  out = act(rules, p, { action: "claim_horde_prize" }, END + 60, { ...ctx, hordeRank: 2 });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.troops.horseman, 50);
  assert.equal(out.state.horde!.trophies, 200, "prize trophies go to the market");
  assert.ok(out.state.castle.resources.gold > 0);
  out = act(rules, out.state, { action: "claim_horde_prize" }, END + 61, { ...ctx, hordeRank: 2 });
  assert.equal(out.error, "You already have your prize.");
  out = act(rules, { ...p, horde_points: 0 }, { action: "claim_horde_prize" }, END + 60, { ...ctx, hordeRank: 1 });
  assert.equal(out.error, "Beat horde camps for points to earn a prize.");
  // Too late once the next horde has arrived.
  out = act(rules, p, { action: "claim_horde_prize" }, START + WEEK + 60, { ...ctx, hordeRank: 1 });
  assert.equal(out.error, "Beat horde camps for points to earn a prize.");
});
