// Treasure chests (server/rules/chests.ts) and the open_chest order.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { checkOpen, openChest, spin, type ChestRules } from "../rules/chests.ts";
import { cofferReward, give, type QuestRules } from "../rules/quests.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const chests: ChestRules = json("data/chests.json");
const quests: QuestRules = json("data/quests.json");
const world: World = json("server/world/world.json");
const T0 = 1_000_000;

test("every wheel has eight real prizes", () => {
  for (const [kind, def] of Object.entries(chests.kinds)) {
    assert.equal(def.wheel.length, 8, kind);
    for (const slot of def.wheel) {
      assert.ok(slot.weight > 0);
      for (const r of Object.keys(slot.reward.resources ?? {})) assert.ok(rules.buildings.resources.includes(r), r);
      for (const u of Object.keys(slot.reward.troops ?? {})) assert.ok(rules.buildings.hasUnit(u), u);
      for (const t of Object.keys(slot.reward.tools ?? {})) assert.ok(rules.buildings.hasTool(t), t);
      for (const c of Object.keys(slot.reward.chests ?? {})) assert.ok(c in chests.kinds, c);
    }
  }
});

test("spins land where the game's do", () => {
  // From scripts/economy/chest_rules.gd, for "Valentin's Castle" with 0 to 11 chests opened.
  const game: Record<string, number[]> = {
    golden: [3, 0, 4, 2, 7, 3, 0, 1, 2, 7, 6, 2],
    iron: [0, 2, 6, 0, 2, 0, 6, 0, 0, 1, 1, 1],
    wooden: [2, 3, 2, 1, 0, 2, 4, 1, 2, 5, 3, 1],
  };
  const castle = CastleState.createNew(rules.buildings, "c", "Valentin's Castle", "player", T0);
  for (const [kind, slots] of Object.entries(game)) {
    slots.forEach((slot, i) => {
      castle.chests.opened = i;
      assert.equal(spin(castle, chests, kind), slot, `${kind} #${i}`);
    });
  }
});

test("opening gives the slot's prize and uses the chest", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", T0);
  assert.equal(checkOpen(castle, chests, "wooden"), "You have no wooden chest.");
  assert.equal(checkOpen(castle, chests, "toString"), "There's no such chest.");
  give(castle, { chests: { golden: 1 }, tools: { ram: 1 } });
  assert.equal(castle.tools.ram, 1);
  const slot = spin(castle, chests, "golden");
  const out = openChest(castle, chests, "golden");
  assert.equal(out.error, "");
  assert.equal(out.slot, slot);
  assert.deepEqual(castle.chests, { have: {}, opened: 1 });
  assert.deepEqual(cofferReward(quests, 1, 1).chests, { wooden: 1 });
});

test("the open_chest order", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  p.castle.chests = { have: { iron: 1 }, opened: 0 };
  assert.equal(act(rules, p, { action: "open_chest", kind: "iron" }, T0, {}).error, "Unknown order.");
  const out = act(rules, p, { action: "open_chest", kind: "iron" }, T0, { chests });
  assert.equal(out.error, "");
  assert.equal(typeof (out.result as { slot: number }).slot, "number");
  assert.deepEqual(out.state.castle.chests, { have: {}, opened: 1 });
  assert.equal(act(rules, out.state, { action: "open_chest", kind: "iron" }, T0, { chests }).error, "You have no iron chest.");
});
