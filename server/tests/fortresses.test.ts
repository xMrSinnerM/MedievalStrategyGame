// Fortresses on the server: the old kingdoms' castles as every player's own
// camps with the fortress numbers (data/fortresses.json), given to players
// who don't have them yet, levelling with each win and rebuilding for long.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { attackCamp, type CampData } from "../rules/baron_camp.ts";
import { act, newPlayer, withFortresses, type PlayerState, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), json("data/villages.json"), json("data/capitals.json"), json("data/fortresses.json"));
const world: World = json("server/world/world.json");
const fr = rules.barons.fortress!;
const T0 = 1_000_000;

test("every castle but yours is a fortress, with its own numbers", () => {
  const castles = json("data/settlements.json").settlements.filter((s: { type: string; id: string }) =>
    s.type === "castle" && s.id !== "player_castle");
  assert.equal(world.fortresses!.length, castles.length);
  assert.equal(rules.barons.forCamp({}), rules.barons);
  assert.equal(rules.barons.forCamp({ fortress: true }), fr);
  const sum = (d: Record<string, number>) => Object.values(d).reduce((a, b) => a + b, 0);
  assert.ok(sum(fr.garrison(1)) > sum(rules.barons.garrison(12)), "a level 1 fortress outdoes a level 12 camp");
  assert.ok(fr.rebuildTime(1) >= 3600, "a beaten lord takes an hour or more to come back");
});

test("new players get the fortresses at level 1, and so do players from before them", () => {
  const p = newPlayer(rules, world, "Newcomer", T0);
  const forts = p.camps.filter((c) => c.fortress);
  assert.equal(forts.length, world.fortresses!.length);
  assert.ok(forts.every((c) => c.level === 1 && c.defeats === 0));
  const old: PlayerState = { ...p, camps: p.camps.filter((c) => !c.fortress) };
  const out = act(rules, old, { action: "state" }, T0, { fortresses: world.fortresses });
  assert.equal(out.state.camps.filter((c) => c.fortress).length, world.fortresses!.length);
  const raised = out.state.camps.map((c) => (c.fortress ? { ...c, level: 7 } : c));
  assert.deepEqual(withFortresses(raised, world.fortresses), raised, "a fortress you raised keeps its level");
});

test("a win against a fortress raises it, carries off its loot and drops better gear", () => {
  const p = newPlayer(rules, world, "Stormer", T0);
  p.castle.troops = { swordsman: 600, horseman: 300 };
  const fort = p.camps.find((c) => c.fortress)!;
  let out = act(rules, p, { action: "attack", camp: fort.id, army: { swordsman: 600, horseman: 300 } }, T0,
    { fortresses: world.fortresses });
  assert.equal(out.error, "");
  const back = out.state.marches[0].back;
  out = act(rules, out.state, { action: "state" }, back + 1, { fortresses: world.fortresses });
  const r = out.reports[0];
  assert.equal(r.winner, "a");
  assert.equal(r.fortress, true);
  assert.equal(r.new_level, 2, "one win a level");
  assert.ok(Object.values(r.spoils).reduce((a, b) => a + b, 0) > 0);
  const after = out.state.camps.find((c) => c.id === fort.id)!;
  assert.equal(after.level, 2);
  const again = act(rules, out.state, { action: "attack", camp: fort.id, army: { swordsman: 1 } }, back + 2,
    { fortresses: world.fortresses });
  assert.notEqual(again.error, "", "still rebuilding");
});

test("the fortress rules, not the baron rules, decide the fight", () => {
  const camp: CampData = { id: "f", name: "F", position: [0, 0], level: 1, defeats: 0, rebuilt_at: 0, fortress: true };
  const small = attackCamp({ ...camp }, rules.barons, rules.buildings, { spearman: 40 }, 1, T0);
  assert.equal(small.winner, "b", "40 spearmen beat a level 1 camp, not a fortress");
  const won = attackCamp(camp, rules.barons, rules.buildings, { swordsman: 600, horseman: 300 }, 1, T0);
  assert.equal(won.winner, "a");
  assert.equal(camp.rebuilt_at, T0 + fr.rebuildTime(1));
});
