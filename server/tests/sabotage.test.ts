// Spies and sabotage (server/rules/sabotage.ts) and the sabotage_camp and
// sabotage_player orders.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { againstCamp, burned, playerKey, stealFrom, wallsFactor, type SabotageRules } from "../rules/sabotage.ts";
import type { CampData } from "../rules/baron_camp.ts";
import { act, fightRaid, newPlayer, sabotagePlayer, type PlayerState, type PvpRules, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const sabotage: SabotageRules = json("data/sabotage.json");
const pvp: PvpRules = json("data/pvp.json");
const world: World = json("server/world/world.json");
const T0 = 1_000_000;

const camp = (level: number): CampData => ({ id: "camp_1", name: "Camp", position: [0, 0], level, defeats: 0, rebuilt_at: 0 });

// From scripts/economy/sabotage_rules.gd: "Valentin's Castle" with k missions sent before, 5 + k agents stealing
// from a camp of level 3 + k % 5: [k, success, stolen].
const GAME: [number, boolean, Record<string, number>][] = [[0,true,{"food":63,"gold":31,"stone":41,"wood":63}],[1,true,{"food":76,"gold":37,"stone":49,"wood":76}],[2,true,{"food":89,"gold":44,"stone":57,"wood":89}],[3,false,{}],[4,false,{}],[5,false,{}],[6,true,{"food":140,"gold":69,"stone":89,"wood":140}],[7,true,{"food":152,"gold":75,"stone":98,"wood":152}],[8,false,{}],[9,true,{"food":178,"gold":89,"stone":114,"wood":178}],[10,false,{}],[11,true,{"food":159,"gold":79,"stone":102,"wood":159}],[12,true,{"food":183,"gold":91,"stone":118,"wood":183}],[13,true,{"food":211,"gold":105,"stone":135,"wood":211}],[14,true,{"food":241,"gold":120,"stone":155,"wood":241}],[15,true,{"food":138,"gold":69,"stone":89,"wood":138}]];

test("missions against camps come out as in the game", () => {
  for (const [k, success, stolen] of GAME) {
    const c = CastleState.createNew(rules.buildings, "c", "Valentin's Castle", "player", T0);
    c.resources = { wood: 0, stone: 0, food: 0, gold: 1000 };
    c.sabotage.count = k;
    const out = againstCamp(c, camp(3 + (k % 5)), rules.barons, sabotage, "steal", 5 + k, T0);
    assert.equal(out.error, "", `#${k}`);
    assert.equal(out.success, success, `#${k}`);
    assert.deepEqual(out.stolen, stolen, `#${k}`);
    assert.equal(c.resources.gold, 1000 - 30 * (5 + k) + (stolen.gold ?? 0));
    assert.equal(c.sabotage.count, k + 1);
  }
});

test("the sabotage_camp order: walls burned and a cooldown", () => {
  let p = newPlayer(rules, world, "Lord", T0);
  p = act(rules, p, { action: "state" }, T0).state;
  p.castle.resources.gold = 1000;
  const id = p.camps[0].id;
  const order = { action: "sabotage_camp", camp: id, mission: "burn_walls", agents: 20 };
  assert.equal(act(rules, p, order, T0).error, "Unknown order.");
  assert.equal(act(rules, p, { ...order, camp: "nope" }, T0, { sabotage }).error, "No such camp.");
  assert.equal(act(rules, p, { ...order, mission: "burn_stores" }, T0, { sabotage }).error, "Camps keep no stores worth burning.");
  // Find a try that succeeds (the luck follows the missions sent).
  let out = act(rules, p, order, T0, { sabotage });
  for (let k = 1; !(out.result as { success: boolean }).success && k < 10; k++) {
    p.castle.sabotage = { ...p.castle.sabotage, count: k, sent: {} };
    out = act(rules, p, order, T0, { sabotage });
  }
  assert.equal(out.error, "");
  const weak = out.state.camps.find((c) => c.id === id)!;
  assert.equal(weak.weak_until, T0 + 6 * 3600);
  assert.equal(weak.weak_cut, 0.3);
  assert.match(act(rules, out.state, order, T0 + 60, { sabotage }).error, /lying low/);
});

test("agents against players: steal, burn and weaken the walls", () => {
  const them = CastleState.createNew(rules.buildings, "t", "Them", "player", T0);
  them.resources = { wood: 1000, stone: 0, food: 1000, gold: 1000 };
  assert.equal(stealFrom(sabotage, them, "wood", 5, 1), Math.min(200, Math.floor((1000 - them.hidden()) * 0.25)));
  assert.equal(stealFrom(sabotage, them, "toString", 5, 1), 0);
  assert.equal(burned(sabotage, them).stone, undefined);
  them.sabotage.walls_until = T0 + 100;
  them.sabotage.walls_cut = 0.3;
  assert.equal(wallsFactor(them, T0), 0.7);
  assert.equal(wallsFactor(them, T0 + 101), 1);
});

test("the sabotage_player order and the target's side", () => {
  const me = act(rules, newPlayer(rules, world, "Lord", T0), { action: "state" }, T0).state;
  const other = act(rules, newPlayer(rules, world, "Other", T0), { action: "state" }, T0).state;
  me.castle.resources.gold = 1000;
  other.castle.resources.wood = 900;
  const target = { name: "Other", home: [other.home_x, other.home_y] as [number, number], level: 1, ally: false, protected: false };
  const ctx = { sabotage, target, targetCastle: other.castle };
  const order = { action: "sabotage_player", target: "Other", mission: "steal", resource: "wood", agents: 20 };
  assert.equal(act(rules, me, { ...order, resource: "toString" }, T0, ctx).error, "Steal which resource?");
  assert.equal(act(rules, me, order, T0, { ...ctx, target: { ...target, protected: true } }).error, "That castle is under beginner protection.");
  assert.equal(act(rules, me, order, T0, { ...ctx, target: { ...target, ally: true } }).error, "Your agents won't work against your own alliance.");
  let out = act(rules, me, order, T0, ctx);
  for (let k = 1; !(out.result as { success: boolean }).success && k < 10; k++) {
    me.castle.sabotage = { ...me.castle.sabotage, count: k, sent: {} };
    out = act(rules, me, order, T0, ctx);
  }
  const sent = out.result as { success: boolean; mission: string; resource: string; stolen: Record<string, number>; target: string };
  assert.equal(out.error, "");
  assert.ok(sent.success && sent.stolen.wood > 0, JSON.stringify(sent));
  assert.equal(out.state.castle.sabotage.sent[playerKey("Other")], T0);
  const hit = sabotagePlayer(rules, sabotage, other, sent, "Lord", 1, 20, T0);
  assert.equal(hit.targetReport.stolen.wood, sent.stolen.wood);
  assert.ok(hit.target.castle.resources.wood < 900);
  assert.equal(hit.targetReport.role, "target");
  assert.equal(hit.senderReport.name, "Other");
  // Weakened walls show in the next battle at their castle.
  const walls = sabotagePlayer(rules, sabotage, other, { ...sent, mission: "burn_walls" }, "Lord", 1, 20, T0);
  assert.equal(walls.target.castle.sabotage.walls_until, T0 + 6 * 3600);
  const raid = { id: 1, attacker_name: "Lord", defender_name: "Other", army: { swordsman: 1 }, from: [0, 0] as [number, number],
    to: [0, 0] as [number, number], depart: T0, arrive: T0 + 10, back: T0 + 20, state: "out" as const, survivors: {}, loot: {} };
  const before = fightRaid(rules, pvp, other as PlayerState, raid).defenderReport.wall;
  const after = fightRaid(rules, pvp, walls.target as PlayerState, raid).defenderReport.wall;
  assert.ok(before > 1 && after < before, `${after} vs ${before}`);
});
