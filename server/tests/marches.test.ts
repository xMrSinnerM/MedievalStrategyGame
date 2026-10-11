// Sent attacks against robber baron camps on the server: marching out,
// fighting, coming home with loot, and camps still rebuilding.
//   node --test server/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type { CampData } from "../rules/baron_camp.ts";
import { CastleState } from "../rules/castle_state.ts";
import { makeRules } from "../rules/load.ts";
import { advanceMarches, checkAttack, marchTimeTo, sendAttack, troopsAway, type Army } from "../rules/marches.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const T0 = 1_000_000;

function world(troops: Record<string, number>): Army {
  const castle = CastleState.createNew(rules.buildings, "home", "Home", "player", T0);
  castle.troops = { ...troops };
  const camps: CampData[] = [
    { id: "baron_0", name: "Near Camp", position: [160, 100], level: 1, defeats: 0, rebuilt_at: 0 },
    { id: "baron_1", name: "Far Camp", position: [100, 1300], level: 20, defeats: 0, rebuilt_at: 0 },
  ];
  return { castle, camps, marches: [], nextMarch: 1, home: [100, 100] };
}

test("march time comes from the distance", () => {
  const w = world({});
  assert.equal(marchTimeTo(w, rules.barons, w.camps[0]), 10); // 60 / 6, at least 10
  assert.equal(marchTimeTo(w, rules.barons, w.camps[1]), 200);
});

test("orders the garrison can't carry out are refused", () => {
  const w = world({ spearman: 10 });
  assert.equal(checkAttack(w, "nowhere", { spearman: 1 }, T0), "No such camp.");
  assert.equal(checkAttack(w, "baron_0", { spearman: 11 }, T0), "Your garrison doesn't have that many soldiers.");
  assert.equal(checkAttack(w, "baron_0", { spearman: 1.5 }, T0), "Your garrison doesn't have that many soldiers.");
  assert.equal(checkAttack(w, "baron_0", { spearman: -1 }, T0), "Your garrison doesn't have that many soldiers.");
  assert.equal(checkAttack(w, "baron_0", { spearman: 0 }, T0), "Choose some soldiers to send.");
  assert.equal(checkAttack(w, "baron_0", { spearman: 5 }, T0), "");
});

test("an army marches out, wins, and comes home with loot", () => {
  const w = world({ spearman: 60, archer: 20 });
  w.castle.resources.wood = 100;
  assert.equal(sendAttack(w, rules.barons, "baron_0", { spearman: 50, archer: 20 }, T0), "");
  assert.deepEqual(w.castle.troops, { spearman: 10, archer: 0 });
  assert.equal(troopsAway(w), 70);
  assert.deepEqual(advanceMarches(w, rules.barons, T0 + 5), [], "nothing happens on the way");

  const reports = advanceMarches(w, rules.barons, T0 + 10);
  assert.equal(reports.length, 1);
  const r = reports[0];
  assert.equal(r.winner, "a");
  assert.equal(r.leveled, true);
  assert.equal(r.new_level, 2);
  assert.ok(r.spoils.wood > 0);
  assert.equal(w.camps[0].level, 2);
  assert.equal(w.camps[0].rebuilt_at, T0 + 10 + rules.barons.rebuildTime(1));
  assert.equal(w.marches[0].state, "home");

  const woodBefore = w.castle.resources.wood;
  advanceMarches(w, rules.barons, T0 + 20);
  assert.equal(w.marches.length, 0, "the march is over");
  const back = Object.values(r.a).reduce((n, s) => n + s.start - s.lost, 0);
  assert.equal(w.castle.troopCount(), 10 + back);
  assert.ok(w.castle.resources.wood > woodBefore + r.spoils.wood - 1, "loot plus the wood cut on the way");
});

test("a second army finds the camp still rebuilding and comes home", () => {
  const w = world({ spearman: 200 });
  sendAttack(w, rules.barons, "baron_0", { spearman: 80 }, T0);
  sendAttack(w, rules.barons, "baron_0", { spearman: 80 }, T0 + 1);
  const reports = advanceMarches(w, rules.barons, T0 + 100);
  assert.equal(reports.length, 2);
  assert.equal(reports[0].empty, false);
  assert.equal(reports[1].empty, true);
  assert.equal(w.marches.length, 0);
  assert.ok(w.castle.troopCount() > 150, "the second army came back whole");
});

test("a lost attack leaves the camp's level and brings no loot", () => {
  const w = world({ spearman: 30 });
  sendAttack(w, rules.barons, "baron_1", { spearman: 30 }, T0);
  const [r] = advanceMarches(w, rules.barons, T0 + 1000);
  assert.equal(r.winner, "b");
  assert.deepEqual(r.spoils, {});
  assert.equal(w.camps[1].level, 20);
  assert.equal(w.camps[1].rebuilt_at, 0);
});

test("loot doesn't overflow the storehouse", () => {
  const w = world({ spearman: 60, archer: 20 });
  const cap = w.castle.storageCapacity();
  w.castle.resources.stone = cap - 5;
  sendAttack(w, rules.barons, "baron_0", { spearman: 60, archer: 20 }, T0);
  advanceMarches(w, rules.barons, T0 + 60);
  assert.equal(w.castle.resources.stone, cap);
});
