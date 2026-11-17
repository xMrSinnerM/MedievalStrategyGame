// The hospital (data/buildings.json, data/units.json "hospital"): some of the
// soldiers lost in battle are only wounded, and are healed for food.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, fightRaid, newPlayer, type PlayerState, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const T0 = 1_000_000;
const sum = (d: Record<string, number> = {}) => Object.values(d).reduce((a, b) => a + b, 0);

/** A player with a finished hospital of this level (0: none). */
function player(level: number, troops: Record<string, number> = {}, spot = world.spots[1]): PlayerState {
  const p = newPlayer(rules, world, "Valentin", T0, spot, pvp);
  p.castle.troops = troops;
  if (level > 0) p.castle.buildings.push({ id: 900, type: "hospital", level, cell: [2, 2], target: 0, finish: 0 });
  for (const r of Object.keys(p.castle.resources)) p.castle.resources[r] = 1200;
  return p;
}

test("a hospital is a building for keep level 2 with more beds at each level", () => {
  const r = rules.buildings;
  assert.equal(r.types.hospital.keep_level, 2);
  assert.equal(r.hospitalBeds(0), 0);
  assert.equal(r.hospitalBeds(1), 20);
  assert.ok(r.hospitalBeds(10) > 500);
  assert.deepEqual(r.healCost("spearman", 10), { food: 110 }, "half of 12 gold + 10 food, in food");
  assert.equal(r.healTime("spearman", 1), 10, "half the training time");
  assert.ok(r.healTime("spearman", 10) < r.healTime("spearman", 1));
  assert.deepEqual(r.healCost("knight"), { food: 50 }, "iron isn't counted");
});

test("an army that loses soldiers at a camp brings 15% of them to the hospital", () => {
  for (const level of [0, 3]) {
    let out = act(rules, player(level, { spearman: 60 }), { action: "state" }, T0 + 1);
    const camp = out.state.camps.reduce((a, b) => (b.level > a.level ? b : a));
    out = act(rules, out.state, { action: "attack", camp: camp.id, army: { spearman: 60 } }, T0 + 2);
    assert.equal(out.error, "");
    const march = out.state.marches[0];
    out = act(rules, out.state, { action: "state" }, march.arrive + 1);
    const report = out.reports[0];
    const fell = report.a.spearman.lost;
    assert.ok(fell >= 10, "a costly fight");
    if (level === 0) {
      assert.equal(report.wounded, undefined);
      assert.deepEqual(out.state.castle.wounded, {});
    } else {
      assert.deepEqual(report.wounded, { spearman: Math.floor(fell * 0.15) });
      assert.deepEqual(out.state.castle.wounded, report.wounded);
    }
  }
});

test("defenders who fall are wounded at 30%, up to the free beds", () => {
  const raid: Raid = { id: 7, attacker_name: "Raider", defender_name: "Valentin", army: { swordsman: 600, archer: 300 },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  const big = fightRaid(rules, pvp, player(8, { spearman: 100 }, world.spots[2]), raid);
  assert.equal(big.defenderReport.b.spearman.lost, 100);
  assert.deepEqual(big.defenderReport.wounded, { spearman: 30 });
  assert.deepEqual(big.defender.castle.wounded, { spearman: 30 });
  assert.equal(big.attackerReport.wounded, undefined, "the attacker isn't told");
  const small = fightRaid(rules, pvp, player(1, { spearman: 100 }, world.spots[2]), raid);
  assert.deepEqual(small.defender.castle.wounded, { spearman: 20 }, "20 beds");
  const none = fightRaid(rules, pvp, player(0, { spearman: 100 }, world.spots[2]), raid);
  assert.deepEqual(none.defender.castle.wounded, {});
  // The raiders' own fallen come home wounded.
  const home = act(rules, player(5), { action: "state" }, T0 + 1300,
    { homecomings: [{ ...raid, state: "home", survivors: { swordsman: 500, archer: 300 }, loot: {} }] });
  assert.deepEqual(home.state.castle.wounded, { swordsman: 15 });
  assert.equal(home.state.castle.troops.swordsman, 500);
  // Soldiers stationed elsewhere or back from helping an ally aren't casualties.
  const helped = act(rules, player(5), { action: "state" }, T0 + 1300, { homecomings: [{ back: T0 + 1200, survivors: { spearman: 5 }, loot: {} }] });
  assert.deepEqual(helped.state.castle.wounded, {});
});

test("healing costs food and time, takes a bed until it is done, and can be stopped", () => {
  const p = player(2);
  p.castle.wounded = { spearman: 12, archer: 3 };
  let out = act(rules, p, { action: "heal", unit: "spearman", amount: 13 }, T0 + 10);
  assert.equal(out.error, "The hospital doesn't have that many wounded");
  out = act(rules, p, { action: "heal", unit: "horseman", amount: 1 }, T0 + 10);
  assert.equal(out.error, "The hospital doesn't have that many wounded");
  out = act(rules, player(0), { action: "heal", unit: "spearman", amount: 1 }, T0 + 10);
  assert.equal(out.error, "Build a hospital first");
  const food = act(rules, p, { action: "state" }, T0 + 10).state.castle.resources.food;
  out = act(rules, p, { action: "heal", unit: "spearman", amount: 10 }, T0 + 10);
  assert.equal(out.error, "");
  assert.ok(Math.abs(food - out.state.castle.resources.food - 110) < 1e-6);
  assert.deepEqual(out.state.castle.wounded, { spearman: 2, archer: 3 });
  const each = rules.buildings.healTime("spearman", 2);
  assert.deepEqual(out.state.castle.healing, [{ unit: "spearman", remaining: 10, unit_time: each, next: T0 + 10 + each }]);
  out = act(rules, out.state, { action: "heal", unit: "archer", amount: 3 }, T0 + 11);
  assert.equal(out.error, "");
  // Four are back after four turns of the healers.
  out = act(rules, out.state, { action: "state" }, T0 + 10 + 4 * each);
  assert.equal(out.state.castle.troops.spearman, 4);
  assert.equal(out.state.castle.healing![0].remaining, 6);
  // Stopping the rest leaves them wounded and gives half of their food back.
  const before = out.state.castle.resources.food;
  out = act(rules, out.state, { action: "cancel_healing", index: 0 }, T0 + 10 + 4 * each);
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.wounded, { spearman: 8 });
  assert.ok(out.state.castle.resources.food - before > 6 * 11 * 0.4);
  assert.equal(out.state.castle.healing![0].unit, "archer");
  out = act(rules, out.state, { action: "state" }, T0 + 100000);
  assert.equal(out.state.castle.troops.archer, 3);
  assert.deepEqual(out.state.castle.healing, []);
  out = act(rules, out.state, { action: "cancel_healing", index: 0 }, T0 + 100001);
  assert.equal(out.error, "No such batch.");
});

test("the beds fill up: the wounded and those being healed both count", () => {
  const p = player(1, { spearman: 400 });
  p.castle.wounded = { archer: 15 };
  let out = act(rules, p, { action: "heal", unit: "archer", amount: 4 }, T0 + 1);
  assert.equal(out.error, "");
  const camp = out.state.camps.reduce((a, b) => (b.level > a.level ? b : a));
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { spearman: 400 } }, T0 + 2);
  const march = out.state.marches[0];
  out = act(rules, out.state, { action: "state" }, march.arrive);
  const c = out.state.castle;
  assert.ok(sum(c.wounded) + sum(Object.fromEntries((c.healing ?? []).map((h, i) => [String(i), h.remaining]))) <= 20);
});
