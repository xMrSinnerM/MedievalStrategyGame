// Capitals on the server: the towns, taken like villages with their own
// rules, and the production boost they give their holder's alliance
// (server/rules/villages.ts, supabase/functions/game/villages.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { rulesFor, untouched, type VillageInfo, type VillageState } from "../rules/villages.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";
import { capitalBoost, resolveVillageRaid, type VillageTarget } from "../../supabase/functions/game/villages.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), json("data/villages.json"), json("data/capitals.json"));
const world: World = json("server/world/world.json");
const c = rules.capitals;
const T0 = 1_000_000;
const HOUR = 3600;

function player(name: string, keep: number, troops: Record<string, number> = {}): PlayerState {
  const p = act(rules, newPlayer(rules, world, name, T0), { action: "state" }, T0).state;
  for (const b of p.castle.buildings) if (b.type === "keep") b.level = keep;
  p.castle.troops = { ...p.castle.troops, ...troops };
  return p;
}

function target(info: VillageInfo, state: VillageState, held = 0, allianceHeld = 0, ally = false): VillageTarget {
  return { info, state, held, ally, allianceHeld };
}

const capitals = world.capitals!;
const town = capitals.find((x) => x.level === 1)!;
const seat = capitals.find((x) => x.level === 2)!;

test("every town is a capital, with its own rules", () => {
  const towns = json("data/settlements.json").settlements.filter((s: { type: string }) => s.type === "town");
  assert.equal(capitals.length, towns.length);
  assert.ok(capitals.every((x) => x.capital === true && x.resource === "gold"));
  assert.equal(capitals.filter((x) => x.level === 2).length, json("data/factions.json").factions.length, "one royal seat a faction");
  assert.equal(rulesFor(rules, town), c);
  assert.equal(rulesFor(rules, world.villages![0]), rules.villages);
});

test("a capital needs a big keep, and you and your alliance can hold only so many", () => {
  const army = { spearman: 10 };
  const militia = untouched(town.id);
  const low = player("Low", c.minKeep - 1, army);
  assert.equal(act(rules, low, { action: "attack_village", army }, T0, { village: target(town, militia) }).error,
    `Your keep must reach level ${c.minKeep} to take a capital.`);
  const p = player("Lord", c.minKeep, army);
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(town, militia, c.perPlayer) }).error,
    "You already hold a capital.");
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(town, militia, 0, c.perAlliance) }).error,
    `Your alliance already holds ${c.perAlliance} capitals.`);
  const friend: VillageState = { ...militia, owner: "Friend", taken_at: 1, paid_at: 1 };
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(town, friend, 0, 0, true) }).error,
    "This capital belongs to your alliance.");
  const fresh: VillageState = { ...militia, owner: "Other", taken_at: T0 - HOUR, paid_at: T0 };
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(town, fresh) }).error,
    "This capital just changed hands and is at peace for now.");
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(town, militia) }).error, "");
});

test("the town guard holds out against a small army and falls to a big one", () => {
  const militia = untouched(seat.id);
  const send = (name: string, army: Record<string, number>) => {
    const out = act(rules, player(name, c.minKeep, army), { action: "attack_village", army }, T0, { village: target(seat, militia) });
    assert.equal(out.error, "");
    return resolveVillageRaid(rules, seat, militia, { ...out.raid!, id: 1 }, true);
  };
  const small = send("Small", { swordsman: 150 });
  assert.equal(small.attackerReport!.winner, "b", "150 swordsmen beat any village, not a royal seat");
  assert.equal(small.attackerReport!.capital, true);
  assert.equal(small.state.owner, "");
  const big = send("Big", { swordsman: 1500, horseman: 600 });
  assert.equal(big.attackerReport!.winner, "a");
  assert.equal(big.attackerReport!.captured, true);
  assert.equal(big.state.owner, "Big");
  assert.ok(big.loot.gold > 0, "the town's gold is carried off");
});

test("capitals your alliance holds make your castle produce more", () => {
  assert.deepEqual(capitalBoost(rules, []), {});
  const p = player("Producer", c.minKeep);
  const plain = act(rules, p, { action: "state" }, T0 + HOUR, { capitalBoost: {} });
  const boosted = act(rules, p, { action: "state" }, T0 + HOUR, { capitalBoost: capitalBoost(rules, [1, 2]) });
  const bonus = c.bonus(1) + c.bonus(2);
  for (const r of rules.buildings.resources) assert.ok(Math.abs(boosted.state.castle.boost[r] - bonus) < 1e-9, r);
  const made = (s: PlayerState) => s.castle.resources.wood - p.castle.resources.wood;
  assert.ok(made(boosted.state) > made(plain.state), "more wood in the same hour");
  assert.deepEqual(act(rules, boosted.state, { action: "state" }, T0 + 2 * HOUR, { capitalBoost: {} }).state.castle.boost, {},
    "the boost goes when the capitals do");
  assert.ok(Math.abs(c.totalBonus([2, 2, 2, 2, 2, 2]) - c.maxBonus) < 1e-9, "it has a ceiling");
});

test("the holder of a capital raises town buildings there, paid from their castle, one at a time", () => {
  const p = player("Builder", c.minKeep);
  const held: VillageState = { ...untouched(town.id), owner: "Builder", taken_at: T0 - 9 * HOUR, paid_at: T0 };
  const order = (s: PlayerState, state: VillageState, building: string, t = T0) =>
    act(rules, s, { action: "build_capital", village: town.id, building }, t, { village: target(town, state, 1) });
  const cost = c.buildingCost("walls", 1);
  p.castle.resources = { ...p.castle.resources, wood: cost.wood - 1, stone: cost.stone };
  assert.equal(order(p, held, "walls").error, "Not enough resources");
  p.castle.resources.wood = cost.wood + 100;
  assert.equal(order(p, held, "palace").error, "There's no such town building.");
  assert.equal(order(p, { ...held, owner: "Other" }, "walls").error, "That capital isn't yours.");
  assert.equal(act(rules, p, { action: "build_capital", village: world.villages![0].id, building: "walls" }, T0,
    { village: target(world.villages![0], held) }).error, "There's no such capital.");
  const out = order(p, held, "walls");
  assert.equal(out.error, "");
  assert.ok(Math.abs(out.state.castle.resources.wood - 100) < 1, "the castle pays");
  const going = out.capitalBuild!.state;
  assert.deepEqual(going.building, { id: "walls", level: 1, finish: T0 + c.buildingTime("walls", 1) });
  assert.equal(c.buildingLevel(going, "walls", T0), 0, "not up yet");
  out.state.castle.resources = { wood: 99999, stone: 99999, food: 99999, gold: 99999 };
  assert.equal(order(out.state, going, "market").error, "The town is already building something.");
  const later = T0 + c.buildingTime("walls", 1);
  assert.equal(c.buildingLevel(going, "walls", later), 1, "done when its time is up");
  assert.ok(c.wallDefense(town, going, later) > c.wallDefense(town, going, T0), "town walls make its walls stronger");
  const next = order(out.state, going, "walls", later);
  assert.equal(next.error, "");
  assert.deepEqual(next.capitalBuild!.state.buildings, { walls: 1 });
  assert.equal(next.capitalBuild!.state.building!.level, 2);
  const top: VillageState = { ...held, buildings: { walls: Number(c.buildings.walls.max_level) } };
  assert.equal(order(out.state, top, "walls").error, "Town Walls is at its highest level.");
});

test("town buildings: more gold, a watch beside the guards, more production for the alliance, and they stay with the town", () => {
  const plain: VillageState = { ...untouched(town.id), owner: "Holder", taken_at: 0, paid_at: T0 };
  const market: VillageState = { ...plain, buildings: { market: 2 } };
  assert.equal(c.rate(town, market, T0), Math.round(c.yieldPerHour("gold", town.level) * (1 + 2 * c.buildings.market.yield_bonus)));
  assert.ok(c.collect(town, market, T0 + HOUR).amount > c.collect(town, plain, T0 + HOUR).amount, "the market sends more gold");

  const guarded: VillageState = { ...plain, guard: { archer: 40 }, buildings: { guardhouse: 3 } };
  const watch = c.watch(town, guarded, T0);
  assert.equal(Object.values(watch).reduce((a, b) => a + b, 0), 3 * c.buildings.guardhouse.guards);
  assert.equal(c.defenders(town, guarded, T0).archer, 40 + (watch.archer ?? 0));
  assert.deepEqual(c.watch(town, { ...guarded, owner: "" }, T0), {}, "no watch for the town guard");
  // A big army takes it: the holder's guards that are left walk home, not the watch.
  const raid = { ...act(rules, player("Taker", c.minKeep, { swordsman: 2000, horseman: 800 }),
    { action: "attack_village", army: { swordsman: 2000, horseman: 800 } }, T0, { village: target(town, guarded) }).raid!, id: 3 };
  const taken = resolveVillageRaid(rules, town, { ...guarded, building: { id: "market", level: 1, finish: raid.arrive + 1 } }, raid, true);
  assert.equal(taken.state.owner, "Taker");
  assert.deepEqual(taken.state.buildings, { guardhouse: 3 }, "the buildings stay with the town");
  assert.equal(taken.state.building, undefined, "one still going up is lost");
  assert.ok((taken.guardHome.archer ?? 0) <= 40, "only the holder's own guards go home");

  assert.deepEqual(capitalBoost(rules, [1], [0]), capitalBoost(rules, [1]));
  const guild = capitalBoost(rules, [1], [3]).wood - capitalBoost(rules, [1]).wood;
  assert.ok(Math.abs(guild - 3 * c.buildings.guildhall.production) < 1e-9, "a guild hall adds production");
  assert.ok(Math.abs(c.totalBonus([2, 2, 2, 2, 2, 2], [5, 5, 5]) - (c.maxBonus + c.guildMax)) < 1e-9, "on top of the ceiling, with its own");
});
