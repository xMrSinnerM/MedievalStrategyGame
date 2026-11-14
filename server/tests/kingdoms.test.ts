// The other kingdoms on the server: founding a castle across the sea,
// building in it, shipping its good home and fighting its robber barons
// (server/rules/kingdoms.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { castleId } from "../rules/kingdoms.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), {}, {}, {}, {}, json("data/kingdoms.json"));
const world: World = json("server/world/world.json");
const T0 = 1_000_000;
const k = rules.kingdoms;
const frost = k.kingdoms.frostmark;

function ready(keep = 3): PlayerState {
  const p = act(rules, newPlayer(rules, world, "Sailor", T0), { action: "state" }, T0).state;
  for (const b of p.castle.buildings) if (b.type === "keep") b.level = keep;
  for (const r of Object.keys(p.castle.resources)) p.castle.resources[r] = 20000;
  return p;
}

test("a castle is founded in a kingdom once the keep is high enough, and its camps join yours", () => {
  const fresh = act(rules, newPlayer(rules, world, "Young", T0), { action: "state" }, T0).state;
  assert.deepEqual(fresh.kingdoms, {});
  assert.equal(act(rules, fresh, { action: "found_kingdom", kingdom: "frostmark" }, T0).error, "Your keep must reach level 3 first.");
  const p = ready();
  assert.equal(act(rules, p, { action: "found_kingdom", kingdom: "atlantis" }, T0).error, "No such kingdom.");
  assert.equal(act(rules, p, { action: "found_kingdom", kingdom: "sunreach" }, T0).error, "Your keep must reach level 4 first.");
  const before = p.camps.length;
  const out = act(rules, p, { action: "found_kingdom", kingdom: "frostmark" }, T0);
  assert.equal(out.error, "");
  const land = out.state.kingdoms!.frostmark;
  assert.equal(land.castle.id, castleId("frostmark"));
  assert.equal(land.castle.name, "Frosthold");
  assert.deepEqual(land.castle.yields, { iron: { rate: frost.yield.rate, store: frost.yield.store } });
  assert.equal(out.state.castle.resources.wood, 20000 - frost.cost.wood, "paid from the main castle");
  assert.equal(out.state.camps.length, before + frost.camps.length);
  assert.equal(out.state.camps.filter((c) => c.kingdom === "frostmark").length, frost.camps.length);
  assert.equal(act(rules, out.state, { action: "found_kingdom", kingdom: "frostmark" }, T0).error, "You already have a castle in Frostmark.");
  // A second kingdom, at keep 4.
  const both = act(rules, { ...ready(4), kingdoms: out.state.kingdoms, camps: out.state.camps }, { action: "found_kingdom", kingdom: "sunreach" }, T0);
  assert.equal(both.error, "");
  assert.deepEqual(Object.keys(both.state.kingdoms!).sort(), ["frostmark", "sunreach"]);
});

test("the kingdom's castle builds what it may and gathers its good, which ships carry home", () => {
  let s = act(rules, ready(), { action: "found_kingdom", kingdom: "frostmark" }, T0).state;
  const id = castleId("frostmark");
  assert.equal(act(rules, s, { action: "place", castle: id, type: "barracks", cell: [2, 2] }, T0).error, "This castle can't have one of these");
  assert.equal(act(rules, s, { action: "place", castle: "kingdom_sunreach", type: "farm", cell: [2, 2] }, T0).error, "You have no castle there.");
  const placed = act(rules, s, { action: "place", castle: id, type: "quarry", cell: [2, 2] }, T0);
  assert.equal(placed.error, "");
  s = placed.state;
  assert.ok(s.kingdoms!.frostmark.castle.buildings.some((b) => b.type === "quarry"));
  assert.ok(!s.castle.buildings.some((b) => b.type === "quarry"), "not built at home");
  assert.equal(act(rules, s, { action: "ship_goods", kingdom: "frostmark" }, T0).error, "There is no iron to ship yet.");
  assert.equal(act(rules, s, { action: "ship_goods", kingdom: "sunreach" }, T0).error, "You have no castle there.");
  // Ten hours later the keep (level 1) has gathered ten hours of iron.
  const later = T0 + 10 * 3600;
  const sent = act(rules, s, { action: "ship_goods", kingdom: "frostmark" }, later);
  assert.equal(sent.error, "");
  const amount = frost.yield.rate * 10;
  assert.deepEqual(sent.state.kingdoms!.frostmark.ships, [{ id: 1, good: "iron", amount, depart: later, arrive: later + frost.voyage }]);
  assert.ok((sent.state.kingdoms!.frostmark.castle.goods!.iron ?? 0) < 1);
  // At sea until the voyage is over, then it is home.
  const half = act(rules, sent.state, { action: "state" }, later + frost.voyage - 1).state;
  assert.equal(half.castle.goods?.iron ?? 0, 0);
  const home = act(rules, sent.state, { action: "state" }, later + frost.voyage).state;
  assert.equal(home.castle.goods!.iron, amount);
  assert.deepEqual(home.kingdoms!.frostmark.ships, []);
  // The store holds only so much.
  const full = act(rules, s, { action: "state" }, T0 + 1000 * 3600).state;
  assert.equal(full.kingdoms!.frostmark.castle.goods!.iron, frost.yield.store);
});

test("armies sail against the kingdom's camps and bring its good home; the good pays for knights", () => {
  let s = act(rules, ready(), { action: "found_kingdom", kingdom: "frostmark" }, T0).state;
  s.castle.troops = { swordsman: 500 };
  const camp = s.camps.find((c) => c.kingdom === "frostmark")!;
  const out = act(rules, s, { action: "attack", camp: camp.id, army: { swordsman: 500 } }, T0);
  assert.equal(out.error, "");
  const m = out.state.marches[0];
  const origin = frost.castle as [number, number];
  const march = rules.barons.marchTime(Math.sqrt((camp.position[0] - origin[0]) ** 2 + (camp.position[1] - origin[1]) ** 2));
  assert.ok(Math.abs(m.arrive - m.depart - (frost.voyage + march)) < 1e-6, "the voyage, then the march from your castle there");
  const done = act(rules, out.state, { action: "state" }, m.back + 1);
  assert.equal(done.reports[0].winner, "a");
  assert.ok(done.reports[0].spoils.iron > 0, "the camp held iron");
  assert.equal(done.state.castle.goods!.iron, done.reports[0].spoils.iron);
  assert.equal(done.state.castle.resources.iron, undefined, "goods are not resources");
  // Knights cost iron.
  s = done.state;
  for (const b of s.castle.buildings) if (b.type === "keep") b.level = 5;
  s.castle.buildings.push({ id: 900, type: "barracks", level: 5, cell: [0, 0], target: 0, finish: 0 });
  const iron = s.castle.goods!.iron;
  const can = Math.floor(iron / 3);
  assert.equal(act(rules, s, { action: "recruit", unit: "knight", amount: can + 1 }, m.back + 1).error, "Not enough resources");
  const trained = act(rules, s, { action: "recruit", unit: "knight", amount: 1 }, m.back + 1);
  assert.equal(trained.error, "");
  assert.equal(trained.state.castle.goods!.iron, iron - 3);
  assert.equal(act(rules, s, { action: "recruit", unit: "marksman", amount: 1 }, m.back + 1).error, "Not enough resources");
});
