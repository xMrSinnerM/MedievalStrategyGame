// The game server's request handling (supabase/functions/game/game.ts),
// without the database.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, castleLevel, checkName, newPlayer, pickSpot, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const T0 = 1_000_000;

test("names", () => {
  assert.equal(checkName("Valentin"), "");
  assert.equal(checkName("Sir Ælfric the 2nd"), "");
  assert.equal(checkName("ab"), "Names are 3 to 20 characters long.");
  assert.equal(checkName("x".repeat(21)), "Names are 3 to 20 characters long.");
  assert.equal(checkName("<script>"), "Use letters, numbers, spaces, ' _ and - only.");
  assert.equal(checkName(42), "Choose a name.");
});

test("a new player gets the starting castle and every camp", () => {
  const p = newPlayer(rules, world, " Valentin ", T0);
  assert.equal(p.name, "Valentin");
  assert.equal(p.castle.name, "Valentin's Castle");
  assert.equal(p.castle.last_update, T0);
  assert.equal(p.camps.length, world.camps.length);
  assert.deepEqual([p.home_x, p.home_y], world.home);
  assert.ok(p.camps.every((c) => c.defeats === 0 && c.rebuilt_at === 0));
});

test("time runs on the server's clock", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  const out = act(rules, p, { action: "state" }, T0 + 3600);
  assert.equal(out.error, "");
  assert.ok(out.state.castle.resources.wood > p.castle.resources.wood + 39, "an hour of wood");
  assert.equal(out.state.castle.last_update, T0 + 3600);
  assert.equal(p.castle.last_update, T0, "the stored state isn't changed in place");
});

test("orders are carried out or refused with a reason", () => {
  let p = newPlayer(rules, world, "Valentin", T0);
  let out = act(rules, p, { action: "place", type: "quarry", cell: [1, 1] }, T0);
  assert.equal(out.error, "");
  assert.equal(typeof out.result, "number");
  p = out.state;
  out = act(rules, p, { action: "place", type: "house", cell: [5, 5] }, T0 + 1);
  assert.equal(out.error, "All builders are busy");
  out = act(rules, p, { action: "place", type: "quarry", cell: "1,1" }, T0);
  assert.equal(out.error, "Bad cell.");
  out = act(rules, p, { action: "place", type: "constructor", cell: [1, 1] }, T0);
  assert.equal(out.error, "Unknown building");
  out = act(rules, p, { action: "recruit", unit: "spearman", amount: 5 }, T0);
  assert.equal(out.error, "Build a barracks first");
  out = act(rules, p, { action: "recruit", unit: "__proto__", amount: 5 }, T0);
  assert.equal(out.error, "Unknown unit");
  out = act(rules, p, { action: "fly" }, T0);
  assert.equal(out.error, "Unknown order.");
  out = act(rules, p, { action: "cancel", id: out.state.castle.buildings.at(-1)!.id }, T0 + 2);
  assert.equal(out.error, "");
});

test("an attack goes out, comes back and is reported once", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  p.castle.troops = { spearman: 300, archer: 100 };
  const near = p.camps.reduce((a, b) =>
    Math.hypot(a.position[0] - p.home_x, a.position[1] - p.home_y) < Math.hypot(b.position[0] - p.home_x, b.position[1] - p.home_y) ? a : b);
  let out = act(rules, p, { action: "attack", camp: near.id, army: { spearman: 300, archer: 100 } }, T0);
  assert.equal(out.error, "");
  assert.equal(out.state.marches.length, 1);
  out = act(rules, out.state, { action: "attack", camp: near.id, army: { constructor: 1 } }, T0);
  assert.equal(out.error, "Unknown unit.");
  out = act(rules, out.state, { action: "attack", camp: near.id, army: [1, 2] }, T0);
  assert.equal(out.error, "Bad army.");
  const back = out.state.marches[0].back;
  out = act(rules, out.state, { action: "state" }, back + 1);
  assert.equal(out.reports.length, 1);
  assert.equal(out.reports[0].winner, "a");
  assert.equal(out.state.marches.length, 0);
  out = act(rules, out.state, { action: "state" }, back + 2);
  assert.equal(out.reports.length, 0, "no second report");
});

test("new players get free spots, and camp levels count from their spot", () => {
  assert.deepEqual(world.spots[0], world.home);
  assert.ok(world.spots.length > 100);
  // At the game's own castle spot the camps start at the levels the game gives them.
  const first = newPlayer(rules, world, "First", T0);
  assert.deepEqual(first.camps.map((c) => c.level), world.camps.map((c) => c.level));
  const taken: [number, number][] = [];
  for (let i = 0; i < world.spots.length; i++) {
    const spot = pickSpot(world, taken);
    assert.ok(spot !== null);
    assert.ok(!taken.some(([x, y]) => x === spot[0] && y === spot[1]));
    taken.push(spot);
  }
  assert.equal(pickSpot(world, taken), null);
  const far = world.spots.reduce((a, b) => (Math.hypot(b[0] - world.home[0], b[1] - world.home[1]) >
    Math.hypot(a[0] - world.home[0], a[1] - world.home[1]) ? b : a));
  const p = newPlayer(rules, world, "Faraway", T0, far);
  assert.deepEqual([p.home_x, p.home_y], far);
  const nearest = p.camps.reduce((a, b) => (Math.hypot(b.position[0] - far[0], b.position[1] - far[1]) <
    Math.hypot(a.position[0] - far[0], a.position[1] - far[1]) ? b : a));
  assert.equal(nearest.level, 1);
  assert.equal(castleLevel(p.castle), 1);
});
