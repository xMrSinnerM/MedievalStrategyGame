// Helping allies (supabase/functions/game/aid.ts and the orders in game.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, fightRaid, newPlayer, spyReport, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";
import { CastleState } from "../rules/castle_state.ts";
import { deliver, recall, stationed, type Aid, type AidRules } from "../../supabase/functions/game/aid.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const aidRules: AidRules = json("data/aid.json");
const T0 = 1_000_000;
const ally = { name: "Bob", home: world.spots[2], protected: true, ally: true };
const travel = rules.barons.marchTime(Math.hypot(world.spots[2][0] - world.spots[1][0], world.spots[2][1] - world.spots[1][1]));

function sender() {
  const p = newPlayer(rules, world, "Ann", T0, world.spots[1], pvp);
  p.castle.resources = { wood: 900, stone: 900, food: 900, gold: 900 };
  p.castle.troops = { spearman: 30, archer: 10 };
  return p;
}

test("sending resources to an ally", () => {
  const p = sender();
  const send = (resources: unknown, target: typeof ally | undefined = ally) =>
    act(rules, p, { action: "send_resources", target: "Bob", resources }, T0, { pvp, target, aid: aidRules });
  assert.equal(act(rules, p, { action: "send_resources", resources: { wood: 10 } }, T0, { aid: aidRules }).error,
    "There's no player by that name.");
  assert.equal(send({ wood: 10 }, { ...ally, ally: false }).error, "You can only help members of your own alliance.");
  assert.equal(send({ wood: 10 }, { ...ally, name: "Ann" }).error, "That's your own castle.");
  assert.equal(send({}).error, "Choose what to send.");
  assert.equal(send({ wood: -5 }).error, "Choose what to send.");
  assert.equal(send({ wood: 1.5 }).error, "Choose what to send.");
  assert.equal(send({ silk: 5 }).error, "Unknown resource.");
  assert.equal(send({ wood: 901 }).error, "You don't have that much wood.");
  // Keep level 1: one cart carries 500.
  assert.equal(send({ wood: 300, stone: 201 }).error, `Your carts carry at most ${aidRules.carry_per_keep_level} at a time.`);
  const out = send({ wood: 300, stone: 200, food: 0 });
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.wood), 600);
  assert.equal(Math.round(out.state.castle.resources.stone), 700);
  assert.deepEqual(out.aid?.resources, { wood: 300, stone: 200 });
  assert.equal(out.aid?.kind, "resources");
  assert.equal(out.aid?.arrive, T0 + travel);
  assert.equal(out.aid?.back, T0 + travel);
  assert.equal(act(rules, p, { action: "send_resources", resources: { wood: 1 } }, T0, { target: ally }).error, "Unknown order.");
});

test("a cart unloads what fits in the ally's storage", () => {
  const bob = newPlayer(rules, world, "Bob", T0, world.spots[2], pvp);
  const cap = CastleState.fromDict(rules.buildings, bob.castle).storageCapacity();
  bob.castle.resources = { wood: 100, stone: cap - 50, food: 100, gold: 100 };
  const cart: Aid = { id: 1, kind: "resources", sender_name: "Ann", receiver_name: "Bob", resources: { wood: 300, stone: 200 },
    army: {}, from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0, leave: T0, back: T0 };
  const out = deliver(rules, bob, cart);
  assert.equal(Math.round(out.receiver.castle.resources.wood), 400);
  assert.equal(Math.round(out.receiver.castle.resources.stone), cap);
  assert.deepEqual(out.receiverReport.resources, { wood: 300, stone: 50 });
  assert.equal(out.receiverReport.name, "Ann");
  assert.deepEqual(out.senderReport.spilled, { stone: 150 });
  assert.equal(out.senderReport.name, "Bob");
});

test("sending defenders, and calling them back", () => {
  const p = sender();
  const send = (army: unknown) => act(rules, p, { action: "send_defenders", target: "Bob", army }, T0, { pvp, target: ally, aid: aidRules });
  assert.equal(send({ spearman: 31 }).error, "Your garrison doesn't have that many soldiers.");
  assert.equal(send({}).error, "Choose some soldiers to send.");
  const out = send({ spearman: 20 });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.troops.spearman, 10);
  const a = out.aid!;
  assert.equal(a.kind, "troops");
  assert.deepEqual(a.army, { spearman: 20 });
  assert.equal(a.leave, T0 + travel + aidRules.station_hours * 3600);
  assert.equal(a.back, a.leave + travel);
  assert.equal(stationed(a, T0 + travel - 1), false);
  assert.equal(stationed(a, T0 + travel), true);
  assert.equal(stationed(a, a.leave), false);
  // On the road they turn round; at the ally's castle they leave now.
  assert.deepEqual(recall(a, T0 + 10), { arrive: T0 + 10, leave: T0 + 10, back: T0 + 20 });
  assert.deepEqual(recall(a, T0 + travel + 100), { arrive: a.arrive, leave: T0 + travel + 100, back: T0 + 2 * travel + 100 });
  assert.equal(recall(a, a.leave + 1), "They're already on their way home.");
  // Home again they rejoin the garrison.
  const home = act(rules, out.state, { action: "state" }, a.back + 1, { homecomings: [{ back: a.back, survivors: { spearman: 18 }, loot: {} }] });
  assert.equal(home.state.castle.troops.spearman, 28);
});

test("allied defenders fight beside the garrison and share the losses", () => {
  const bob = newPlayer(rules, world, "Bob", T0, world.spots[2], pvp);
  bob.castle.troops = { spearman: 20 };
  const raid: Raid = { id: 3, attacker_name: "Raider", defender_name: "Bob", army: { spearman: 60, archer: 30 },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  const alone = fightRaid(rules, pvp, bob, raid);
  assert.equal(alone.attackerReport.winner, "a");
  assert.deepEqual(alone.helpers, []);
  const helped = fightRaid(rules, pvp, bob, raid, [{ spearman: 60, archer: 20 }, { spearman: 20 }]);
  assert.equal(helped.attackerReport.winner, "b", "with help the castle holds");
  const b = helped.attackerReport.b;
  assert.equal(b.spearman.start, 100);
  assert.equal(b.archer.start, 20);
  // Every soldier lost comes from one of the groups, in proportion.
  const left = (helped.defender.castle.troops.spearman ?? 0) + helped.helpers.reduce((n, h) => n + (h.spearman ?? 0), 0);
  assert.equal(left, 100 - b.spearman.lost);
  assert.equal(helped.helpers[0].archer ?? 0, 20 - b.archer.lost);
  assert.ok(Math.abs((20 - helped.defender.castle.troops.spearman) - (20 - (helped.helpers[1].spearman ?? 0))) <= 1);
  // A spy sees the allied defenders too.
  assert.deepEqual(spyReport(rules, pvp, bob, T0, [{ spearman: 5, archer: 2 }]).troops, { spearman: 25, archer: 2 });
});
