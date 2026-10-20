// Outposts on the server: founding a second castle, building in it, its
// region's bonus, and carts between the two castles (server/rules/outposts.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { nearestSpot } from "../rules/outposts.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"));
const world: World = json("server/world/world.json");
const T0 = 1_000_000;
const o = rules.outposts;

function ready(): PlayerState {
  const p = act(rules, newPlayer(rules, world, "Founder", T0), { action: "state" }, T0).state;
  for (const b of p.castle.buildings) if (b.type === "keep") b.level = o.keepNeeded;
  for (const r of Object.keys(p.castle.resources)) p.castle.resources[r] = 9000;
  return p;
}

test("an outpost is founded on the nearest free spot, once the keep is high enough", () => {
  const fresh = act(rules, newPlayer(rules, world, "Young", T0), { action: "state" }, T0).state;
  const spot = nearestSpot(world.spots, [fresh.home_x, fresh.home_y], []);
  assert.ok(spot);
  assert.equal(act(rules, fresh, { action: "found_outpost", region: "wood" }, T0, { outpostSpot: spot }).error,
    `Your keep must reach level ${o.keepNeeded} first.`);
  const p = ready();
  assert.equal(act(rules, p, { action: "found_outpost", region: "silk" }, T0, { outpostSpot: spot }).error,
    "Choose a region for your outpost.");
  assert.equal(act(rules, p, { action: "found_outpost", region: "wood" }, T0, { outpostSpot: null }).error,
    "There's no free land for an outpost.");
  const out = act(rules, p, { action: "found_outpost", region: "wood" }, T0, { outpostSpot: spot });
  assert.equal(out.error, "");
  const op = out.state.outpost!;
  assert.deepEqual([op.x, op.y, op.name, op.region], [spot[0], spot[1], "Timberland", "wood"]);
  assert.deepEqual(op.castle.boost, { wood: 0.5 });
  assert.equal(out.state.castle.resources.wood, 9000 - o.cost.wood, "paid from the main castle");
  assert.equal(act(rules, out.state, { action: "found_outpost", region: "stone" }, T0, { outpostSpot: spot }).error,
    "You already have an outpost.");
});

test("an outpost builds only what it may, and its region makes more", () => {
  const p = ready();
  const spot = nearestSpot(world.spots, [p.home_x, p.home_y], [])!;
  let s = act(rules, p, { action: "found_outpost", region: "wood" }, T0, { outpostSpot: spot }).state;
  assert.equal(act(rules, s, { action: "place", castle: "outpost", type: "barracks", cell: [2, 2] }, T0).error,
    "An outpost can't have one of these");
  assert.equal(act(rules, { ...s, outpost: null }, { action: "place", castle: "outpost", type: "woodcutter", cell: [2, 2] }, T0).error,
    "You have no outpost.");
  const before = s.castle.buildings.length;
  const out = act(rules, s, { action: "place", castle: "outpost", type: "woodcutter", cell: [2, 2] }, T0);
  assert.equal(out.error, "");
  s = out.state;
  assert.equal(s.castle.buildings.length, before, "the main castle is untouched");
  assert.ok(s.outpost!.castle.buildings.some((b) => b.type === "woodcutter"));
  // Both castles build on their own.
  s = act(rules, s, { action: "place", type: "woodcutter", cell: [2, 2] }, T0).state;
  s = act(rules, s, { action: "state" }, T0 + 86_400).state;
  const at = (c: PlayerState["castle"]) => c.buildings.find((b) => b.type === "woodcutter")!;
  assert.equal(at(s.castle).level, 1);
  assert.equal(at(s.outpost!.castle).level, 1);
  const keep = s.outpost!.castle.buildings.find((b) => b.type === "keep")!;
  keep.level = o.keepCap;
  assert.equal(act(rules, s, { action: "upgrade", castle: "outpost", id: keep.id }, T0 + 86_400).error,
    "An outpost's keep can't go higher");
});

test("carts carry resources between your castles", () => {
  const p = ready();
  const spot = nearestSpot(world.spots, [p.home_x, p.home_y], [])!;
  let s = act(rules, p, { action: "found_outpost", region: "stone" }, T0, { outpostSpot: spot }).state;
  assert.equal(act(rules, s, { action: "send_carts", resources: {} }, T0).error, "Load something onto the carts.");
  assert.equal(act(rules, s, { action: "send_carts", from: "outpost", resources: { wood: 1e6 } }, T0).error, "Not enough resources.");
  const wood = s.castle.resources.wood;
  const out = act(rules, s, { action: "send_carts", resources: { wood: 300 } }, T0);
  assert.equal(out.error, "");
  s = out.state;
  const cart = s.outpost!.carts[0];
  assert.equal(cart.to, "outpost");
  assert.equal(cart.arrive, T0 + rules.barons.marchTime(Math.hypot(spot[0] - s.home_x, spot[1] - s.home_y)));
  assert.ok(Math.abs(s.castle.resources.wood - (wood - 300)) < 1e-6);
  const there = s.outpost!.castle.resources.wood;
  s = act(rules, s, { action: "state" }, cart.arrive - 1).state;
  assert.equal(s.outpost!.carts.length, 1, "still on the road");
  s = act(rules, s, { action: "state" }, cart.arrive + 1).state;
  assert.equal(s.outpost!.carts.length, 0);
  assert.ok(s.outpost!.castle.resources.wood >= there + 300, "the wood arrived");
});
