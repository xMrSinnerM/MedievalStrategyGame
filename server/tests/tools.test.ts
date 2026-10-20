// Siege tools: the workshop, attack tools on camps and players, and defence
// tools on the walls (server/rules/battle.ts wallMods(), checkTools()).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { checkTools, siegeOdds, wallMods, DEFAULT_LAYOUT, siege } from "../rules/battle.ts";
import { act, fightRaid, newPlayer, spyReport, type PlayerState, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const T0 = 1_000_000;
const b = rules.buildings;

function withBuildings(p: PlayerState, levels: Record<string, number>): PlayerState {
  const buildings = p.castle.buildings.map((x) => (x.type in levels ? { ...x, level: levels[x.type] } : x));
  let id = 90;
  for (const [type, level] of Object.entries(levels)) {
    if (!buildings.some((x) => x.type === type)) buildings.push({ id: id++, type, level, cell: [0, id], target: 0, finish: 0 });
  }
  return { ...p, castle: { ...p.castle, buildings } };
}

test("what tools do at a wall", () => {
  assert.deepEqual(wallMods(b, 2, {}, {}), { wall: 2, a: 1, b: 1 }, "no tools, no change");
  assert.equal(wallMods(b, 2, { ladder: 5 }, {}).wall, 1.6, "5 ladders take 40% off the bonus");
  assert.equal(wallMods(b, 2, { ladder: 10, ram: 4 }, {}).wall, 1, "never below no wall at all");
  assert.equal(wallMods(b, 2, {}, { moat: 4 }).wall, 2.4, "a moat makes the wall stronger");
  const m = wallMods(b, 1.5, { mantlet: 20 }, { arrow_slits: 2, pitch: 3 });
  assert.equal(m.b, 0.5 * 1.1, "mantlets halve the defenders' damage at most, arrow slits add to it");
  assert.equal(m.a, 0.85, "pitch hurts the attackers");
  // Ladders help: the same attack does better with them.
  const waves = [{ front: { swordsman: 50 } }];
  const without = siegeOdds(b, waves, { spearman: 120 }, DEFAULT_LAYOUT, 1, 2.2);
  const with8 = siegeOdds(b, waves, { spearman: 120 }, DEFAULT_LAYOUT, 1, 2.2, { a: { front: { ladder: 8 } } });
  assert.ok(with8 > without, `${with8} > ${without}`);
});

test("which tools may go where", () => {
  const stock = { ladder: 5, ram: 2, arrow_slits: 3 };
  assert.deepEqual(checkTools(b, undefined, "attack", 4, stock), {});
  assert.deepEqual(checkTools(b, { left: { ladder: 2, mantlet: 0 }, front: { ram: 2 } }, "attack", 4, stock),
    { left: { ladder: 2 }, front: { ram: 2 } });
  assert.equal(checkTools(b, { left: { ram: 1 } }, "attack", 4, stock), "Battering ram can't be used at the left wall.");
  assert.equal(checkTools(b, { left: { arrow_slits: 1 } }, "attack", 4, stock), "Unknown siege tool.");
  assert.equal(checkTools(b, { left: { ladder: 5 } }, "attack", 4, stock), "Only 4 siege tools fit on each wall.");
  assert.equal(checkTools(b, { left: { ladder: 3 }, right: { ladder: 3 } }, "attack", 4, stock), "You don't have that many siege tools.");
  assert.equal(checkTools(b, { gate: { ladder: 1 } }, "attack", 4, stock), "Bad tools.");
  assert.equal(checkTools(b, { left: { ladder: 1.5 } }, "attack", 4, stock), "Bad tools.");
  assert.equal(checkTools(b, { left: { arrow_slits: 1 } }, "defence", 0, stock), "No siege tools fit there yet.");
});

test("the workshop builds tools one after another", () => {
  let p = newPlayer(rules, world, "Smith", T0);
  assert.equal(act(rules, p, { action: "craft", tool: "ladder", amount: 2 }, T0).error, "Build a siege workshop first");
  p = withBuildings(p, { workshop: 1 });
  assert.equal(act(rules, p, { action: "craft", tool: "ram", amount: 1 }, T0).error, "Needs workshop level 5");
  let out = act(rules, p, { action: "craft", tool: "ladder", amount: 3 }, T0);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.resources.wood, p.castle.resources.wood - 180);
  assert.equal(out.state.castle.stats.spent, 180, "tools count as spending for the daily tasks");
  out = act(rules, out.state, { action: "state" }, T0 + 41);
  assert.deepEqual(out.state.castle.tools, { ladder: 2 }, "20 seconds each");
  assert.equal(out.state.castle.crafting[0].remaining, 1);
  out = act(rules, out.state, { action: "cancel_crafting", index: 0 }, T0 + 42);
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.crafting, []);
  assert.deepEqual(out.state.castle.tools, { ladder: 2 });
  assert.equal(act(rules, out.state, { action: "cancel_crafting", index: 0 }, T0 + 43).error, "No such batch.");
});

test("attack tools go with an army against a camp and are used up", () => {
  let p = withBuildings(newPlayer(rules, world, "Raider", T0), { keep: 2 });
  p = { ...p, castle: { ...p.castle, troops: { swordsman: 40 }, tools: { ladder: 6 } } };
  const camp = p.camps[0].id;
  const attack = (tools: unknown) =>
    act(rules, p, { action: "attack", camp, waves: [{ front: { swordsman: 40 } }], tools }, T0);
  assert.equal(attack({ front: { ladder: 5 } }).error, "Only 4 siege tools fit on each wall.");
  const out = attack({ front: { ladder: 4 } });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.tools, { ladder: 2 });
  assert.deepEqual(out.state.marches[0].tools, { front: { ladder: 4 } });
  const fought = act(rules, out.state, { action: "state" }, out.state.marches[0].arrive + 1);
  assert.deepEqual(fought.reports[0].tools, { a: { front: { ladder: 4 } }, b: {}, lost: {} });
});

test("defence tools stand on the walls, show to spies, and fall with their wall", () => {
  let p = withBuildings(newPlayer(rules, world, "Victim", T0, world.spots[2], pvp), { wall: 2 });
  p = { ...p, castle: { ...p.castle, tools: { arrow_slits: 4, moat: 2 } } };
  assert.equal(act(rules, p, { action: "set_tools", tools: { left: { arrow_slits: 5 } } }, T0).error,
    "Only 4 siege tools fit on each wall.");
  assert.equal(act(rules, p, { action: "set_tools", tools: { left: { ladder: 1 } } }, T0).error, "Unknown siege tool.");
  const set = act(rules, p, { action: "set_tools", tools: { left: { arrow_slits: 4 }, front: { moat: 2 } } }, T0);
  assert.equal(set.error, "");
  const victim = { ...set.state, castle: { ...set.state.castle, troops: { spearman: 40 } } };
  assert.deepEqual(spyReport(rules, pvp, victim, T0).tools, { left: { arrow_slits: 4 }, front: { moat: 2 } });
  // A big army breaks every wall: the arrow slits and the moat are lost.
  const raid: Raid = { id: 4, attacker_name: "Raider", defender_name: "Victim", army: { swordsman: 600 },
    waves: [{ left: { swordsman: 200 }, front: { swordsman: 200 }, right: { swordsman: 200 } }], tools: { front: { ladder: 2 } },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  const out = fightRaid(rules, pvp, victim, raid);
  assert.equal(out.attackerReport.winner, "a");
  assert.deepEqual(out.attackerReport.tools?.lost, { left: { arrow_slits: 4 }, front: { moat: 2 } });
  assert.deepEqual(out.defender.castle.tools, {});
  assert.deepEqual(out.defender.castle.defence_tools, {});
  // A wall that holds keeps its tools.
  const held = fightRaid(rules, pvp, victim, { ...raid, army: { spearman: 5 }, waves: [{ right: { spearman: 5 } }] });
  assert.equal(held.attackerReport.winner, "b");
  assert.deepEqual(held.defender.castle.defence_tools, { left: { arrow_slits: 4 }, front: { moat: 2 } });
  // The same siege without the defenders' tools: arrow slits make the left wall harder.
  const bare = siege(b, [{ left: { swordsman: 30 } }], { spearman: 40 }, { left: 100, front: 0, right: 0, courtyard: 0 }, 9, 1.4);
  const slits = siege(b, [{ left: { swordsman: 30 } }], { spearman: 40 }, { left: 100, front: 0, right: 0, courtyard: 0 }, 9, 1.4,
    { b: { left: { arrow_slits: 4 } } });
  assert.ok(slits.a.swordsman.lost > bare.a.swordsman.lost);
});

test("attack tools against a player leave the store with the army", () => {
  let me = withBuildings(newPlayer(rules, world, "Raider", T0, world.spots[1], pvp), { keep: 3 });
  me = { ...me, protected_until: 0, castle: { ...me.castle, troops: { swordsman: 20 }, tools: { ladder: 3 } } };
  const target = { name: "Victim", home: world.spots[2], protected: false, level: 3 };
  const send = (tools: unknown) => act(rules, me, { action: "attack_player", target: "Victim", army: { swordsman: 20 }, tools },
    T0, { pvp, target });
  assert.equal(send({ left: { ladder: 4 } }).error, "You don't have that many siege tools.");
  const out = send({ left: { ladder: 3 } });
  assert.equal(out.error, "");
  assert.deepEqual(out.raid?.tools, { left: { ladder: 3 } });
  assert.deepEqual(out.state.castle.tools, {});
});
