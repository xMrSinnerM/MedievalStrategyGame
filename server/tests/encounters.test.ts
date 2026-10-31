// Random map encounters (server/rules/encounters.ts) and the encounter order.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { activeEncounters, encounterRules, takeEncounter } from "../rules/encounters.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const encounters = encounterRules(json("data/encounters.json"), json("data/roads.json"));
const world: World = json("server/world/world.json");
const T = 1_800_000_000;

// From scripts/economy/encounter_rules.gd at T: [id, kind, road, at, variant, start].
const GAME_LIST = [["e0-83333", "treasure", 20, 362, 30, 1799992800.0], ["e1-83333", "bandits", 45, 446, 628, 1799990100.0], ["e2-83333", "bandits", 8, 380, 128, 1799987400.0], ["e3-83333", "bandits", 5, 464, 78, 1799984700.0], ["e4-83333", "caravan", 5, 312, 346, 1799982000.0], ["e5-83333", "caravan", 16, 313, 759, 1799979300.0], ["e6-83334", "bandits", 7, 330, 565, 1799998200.0], ["e7-83334", "treasure", 11, 616, 949, 1799995500.0]];
// Taking each on with "Valentin's Castle", 14 spearmen and 6 archers, all sent: [id, won, troops after, reward].
const GAME_RESULTS = [["e0-83333", null, {"archer": 6, "spearman": 14}, {"chests": {"wooden": 1}, "resources": {"gold": 100}}], ["e1-83333", true, {"archer": 1, "spearman": 7}, {"resources": {"food": 250, "gold": 80, "stone": 300, "wood": 300}}], ["e2-83333", true, {"archer": 1, "spearman": 7}, {"resources": {"food": 250, "gold": 80, "stone": 300, "wood": 300}}], ["e3-83333", false, {"archer": 1, "spearman": 5}, {}], ["e4-83333", null, {"archer": 6, "spearman": 14}, {"resources": {"gold": 160}}], ["e5-83333", null, {"archer": 6, "spearman": 14}, {"resources": {"food": 1000}}], ["e6-83334", false, {"spearman": 4}, {}], ["e7-83334", null, {"archer": 6, "spearman": 14}, {"chests": {"wooden": 1}, "resources": {"gold": 100}}]];

test("the same encounters are on the map as in the game", () => {
  assert.deepEqual(activeEncounters(encounters, T).map((e) => [e.id, e.kind, e.road, e.at, e.variant, e.start]), GAME_LIST);
});

test("taking them on comes out as in the game", () => {
  for (const [id, won, troops, reward] of GAME_RESULTS) {
    const castle = CastleState.createNew(rules.buildings, "c", "Valentin's Castle", "player", 1_000_000);
    castle.troops = { spearman: 14, archer: 6 };
    castle.resources = { wood: 5000, stone: 5000, food: 5000, gold: 5000 };
    const out = takeEncounter(castle, encounters, id, "all", T);
    assert.equal(out.error, "", id);
    assert.equal(out.won ?? null, won, id);
    assert.deepEqual(castle.troops, troops, id);
    assert.deepEqual(out.reward, reward, id);
    assert.equal(takeEncounter(castle, encounters, id, "all", T).error === "", won === false, `${id} once won`);
  }
});

test("the encounter order", () => {
  const p = newPlayer(rules, world, "Valentin", T);
  const id = GAME_LIST.find((e) => e[1] === "caravan")![0] as string;
  assert.equal(act(rules, p, { action: "encounter", id }, T, {}).error, "Unknown order.");
  assert.equal(act(rules, p, { action: "encounter", id: "e0-1" }, T, { encounters }).error, "That's gone from the map.");
  const out = act(rules, p, { action: "encounter", id }, T, { encounters });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.encounters.done, [id]);
  assert.equal(act(rules, out.state, { action: "encounter", id }, T, { encounters }).error, "You've already been there.");
});
