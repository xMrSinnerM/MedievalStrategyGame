// Commanders and gear on the server: commanders lead attacks on camps and
// players, barons drop gear, and orders equip, unequip and sell it
// (server/rules/gear.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { siege, DEFAULT_LAYOUT } from "../rules/battle.ts";
import type { Item } from "../rules/gear.ts";
import { godotHash } from "../rules/util.ts";
import { act, fightRaid, newPlayer, spyReport, type PlayerState, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const T0 = 1_000_000;
const g = rules.gear;

function item(id: number, slot: string, side: "attack" | "defence", stats: Record<string, number>): Item {
  return { id, slot, side, rarity: "epic", name: `Test ${slot}`, stats };
}

function withKeep(p: PlayerState, level: number): PlayerState {
  return { ...p, castle: { ...p.castle, buildings: p.castle.buildings.map((b) => (b.type === "keep" ? { ...b, level } : b)) } };
}

test("a castle gets commanders as its keep grows", () => {
  let p = newPlayer(rules, world, "Lord", T0);
  p = act(rules, p, { action: "state" }, T0).state;
  assert.deepEqual(p.castle.armoury.commanders.map((c) => c.name), ["Sir Edric Vane"]);
  p = act(rules, withKeep(p, 5), { action: "state" }, T0 + 1).state;
  assert.equal(p.castle.armoury.commanders.length, 3);
});

test("gear makes a commander stronger, and levels add to it", () => {
  assert.deepEqual(g.effects({}), {});
  const fx = g.effects({ weapon: item(1, "weapon", "attack", { wall_attack: 12, wall_cut: 9 }),
    banner: item(2, "banner", "attack", { loot: 15, wall_cut: 50 }) }, 3);
  assert.deepEqual(fx, { wall_attack: 0.16, yard_attack: 0.04, wall_cut: 0.5, loot: 0.15 }, "wall cut is capped at 50%");
  assert.equal(g.levelFor(0), 1);
  assert.equal(g.levelFor(5), 2);
  assert.equal(g.levelFor(10_000), 10);
  // A commander's bonus wins sieges.
  const waves = [{ front: { swordsman: 50 } }];
  let plain = 0;
  let led = 0;
  for (let s = 0; s < 40; s++) {
    if (siege(rules.buildings, waves, { spearman: 150 }, DEFAULT_LAYOUT, s, 2).winner === "a") plain++;
    if (siege(rules.buildings, waves, { spearman: 150 }, DEFAULT_LAYOUT, s, 2,
      { lead_a: { wall_attack: 0.4, yard_attack: 0.4, wall_cut: 0.3 } }).winner === "a") led++;
  }
  assert.ok(led > plain, `${led} > ${plain}`);
});

test("gear is worn, swapped, taken off and sold", () => {
  let p = act(rules, newPlayer(rules, world, "Smith", T0), { action: "state" }, T0).state;
  p.castle.armoury.bag = [item(1, "helmet", "attack", { wall_attack: 8 }), item(2, "helmet", "attack", { wall_cut: 9 }),
    item(3, "banner", "defence", { wall_bonus: 10 })];
  p.castle.armoury.next_item = 4;
  const order = (req: Record<string, unknown>) => act(rules, p, req, T0 + 5);
  assert.equal(order({ action: "equip", who: 1, item: 3 }).error, "Commanders wear attack gear.");
  assert.equal(order({ action: "equip", who: "castellan", item: 1 }).error, "The castellan wears defence gear.");
  assert.equal(order({ action: "equip", who: 7, item: 1 }).error, "No such commander.");
  assert.equal(order({ action: "equip", who: 1, item: 99 }).error, "There's no such item in your bag.");
  let out = order({ action: "equip", who: 1, item: 1 });
  assert.equal(out.error, "");
  p = out.state;
  out = order({ action: "equip", who: 1, item: 2 });
  p = out.state;
  assert.equal(p.castle.armoury.commanders[0].gear.helmet.id, 2, "the new helmet is worn");
  assert.deepEqual(p.castle.armoury.bag.map((x) => x.id), [3, 1], "the old one is back in the bag");
  p = order({ action: "equip", who: "castellan", item: 3 }).state;
  assert.equal(p.castle.armoury.castellan.banner.id, 3);
  assert.equal(order({ action: "unequip", who: 1, slot: "boots" }).error, "Nothing is worn there.");
  p = order({ action: "unequip", who: 1, slot: "helmet" }).state;
  assert.deepEqual(p.castle.armoury.commanders[0].gear, {});
  const gold = p.castle.resources.gold;
  out = order({ action: "sell_gear", item: 1 });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.resources.gold, gold + 600, "an epic item sells for 600 gold");
});

test("a commander leads an army against a camp, earns xp and brings home gear", () => {
  let p = act(rules, newPlayer(rules, world, "Raider", T0), { action: "state" }, T0).state;
  p.castle.troops = { swordsman: 200 };
  p.castle.armoury.commanders[0].gear = { weapon: item(1, "weapon", "attack", { loot: 20 }) };
  const camp = p.camps[0].id;
  assert.equal(act(rules, p, { action: "attack", camp, army: { swordsman: 100 }, commander: 5 }, T0).error, "No such commander.");
  let out = act(rules, p, { action: "attack", camp, army: { swordsman: 100 }, commander: 1 }, T0);
  assert.equal(out.error, "");
  const m = out.state.marches[0];
  assert.deepEqual(m.lead, { id: 1, name: "Sir Edric Vane", fx: { loot: 0.2 } });
  assert.equal(out.state.castle.armoury.commanders[0].away_until, m.back);
  assert.equal(act(rules, out.state, { action: "attack", camp: p.camps[1].id, army: { swordsman: 10 }, commander: 1 }, T0 + 1).error,
    "Sir Edric Vane is still away with an army.");
  assert.equal(act(rules, out.state, { action: "equip", who: 1, item: 1 }, T0 + 1).error, "Sir Edric Vane is away with an army.");
  out = act(rules, out.state, { action: "state" }, m.arrive + 1);
  const report = out.reports[0];
  assert.equal(report.winner, "a");
  assert.deepEqual(report.lead, { id: 1, name: "Sir Edric Vane", xp: report.level, level: 1, leveled: false });
  assert.equal(out.state.castle.armoury.commanders[0].xp, report.level);
  // What the camp dropped (if anything) is the same as rolling it again.
  const seed = m.id * 7919 + godotHash(camp);
  const drop = g.rollDrop(report.level, seed + 31337);
  if (drop) {
    assert.equal(report.gear?.name, drop.name);
    assert.equal(out.state.castle.armoury.bag[0].name, drop.name);
  } else {
    assert.equal(report.gear, undefined);
  }
});

test("a full bag loses the drop", () => {
  let p = act(rules, newPlayer(rules, world, "Hoarder", T0), { action: "state" }, T0).state;
  p.castle.troops = { swordsman: 300 };
  p.castle.armoury.bag = Array.from({ length: g.bagSize }, (_, i) => item(i + 1, "helmet", "attack", { wall_attack: 2 }));
  // Find a march id whose fight drops something.
  const camp = p.camps[0];
  let tries = 0;
  while (g.rollDrop(camp.level, p.next_march * 7919 + godotHash(camp.id) + 31337) === null && tries < 50) {
    p = { ...p, next_march: p.next_march + 1 };
    tries++;
  }
  const out = act(rules, p, { action: "attack", camp: camp.id, army: { swordsman: 300 } }, T0);
  const fought = act(rules, out.state, { action: "state" }, out.state.marches[0].arrive + 1);
  assert.equal(fought.reports[0].winner, "a");
  assert.equal(fought.reports[0].bag_full, true);
  assert.equal(fought.state.castle.armoury.bag.length, g.bagSize);
});

test("commanders against players: the castellan defends, xp waits until the army is home", () => {
  let me = act(rules, withKeep(newPlayer(rules, world, "Raider", T0, world.spots[1], pvp), 3), { action: "state" }, T0).state;
  me = { ...me, protected_until: 0, castle: { ...me.castle, troops: { swordsman: 60 } } };
  me.castle.armoury.commanders[0].gear = { weapon: item(1, "weapon", "attack", { wall_attack: 10 }) };
  const target = { name: "Victim", home: world.spots[2], protected: false, level: 3 };
  const sent = act(rules, me, { action: "attack_player", target: "Victim", army: { swordsman: 60 }, commander: 1 }, T0, { pvp, target });
  assert.equal(sent.error, "");
  assert.deepEqual(sent.raid?.lead, { id: 1, name: "Sir Edric Vane", fx: { wall_attack: 0.1 } });
  const victim = act(rules, newPlayer(rules, world, "Victim", T0, world.spots[2], pvp), { action: "state" }, T0).state;
  victim.castle.troops = { spearman: 30 };
  victim.castle.armoury.castellan = { banner: item(5, "banner", "defence", { wall_bonus: 10, wall_defence: 12 }) };
  assert.deepEqual(spyReport(rules, pvp, victim, T0).castellan, { wall_defence: 0.12, wall_bonus: 0.1 });
  const raid: Raid = { id: 3, ...sent.raid! };
  const fought = fightRaid(rules, pvp, victim, raid);
  const xp = fought.attackerReport.winner === "a" ? g.xpPlayerWin : g.xpLoss;
  assert.deepEqual(fought.attackerReport.lead, { id: 1, name: "Sir Edric Vane", xp });
  assert.equal(fought.defenderReport.lead, undefined);
  assert.equal(fought.lead?.xp, xp);
  // Home again: the xp lands.
  const home = act(rules, sent.state, { action: "state" }, raid.back + 1,
    { homecomings: [{ back: raid.back, survivors: fought.survivors, loot: fought.loot, lead: fought.lead }] });
  assert.equal(home.state.castle.armoury.commanders[0].xp, xp);
});

test("commanders learn skills with the points their levels earn", () => {
  let p = newPlayer(rules, world, "Lord", T0);
  p = act(rules, p, { action: "state" }, T0).state;
  const learn = (s: PlayerState, skill: unknown) => act(rules, s, { action: "learn_skill", commander: 1, skill }, T0);
  assert.equal(learn(p, "sapper").error, "Sapper needs level 2.");
  p.castle.armoury.commanders[0].xp = 30;
  p.castle.armoury.commanders[0].level = g.levelFor(30);
  assert.equal(learn(p, "wallbreaker").error, "Learn Sapper first.");
  assert.equal(learn(p, "breach_master").error, "Master of the Breach needs level 7.");
  assert.equal(learn(p, "toString").error, "There's no such skill.");
  assert.equal(act(rules, p, { action: "learn_skill", commander: 9, skill: "sapper" }, T0).error, "No such commander.");
  for (const skill of ["sapper", "sapper", "wallbreaker"]) {
    const out = learn(p, skill);
    assert.equal(out.error, "", skill);
    p = out.state;
  }
  const c = p.castle.armoury.commanders[0];
  assert.deepEqual(c.skills, { sapper: 2, wallbreaker: 1 });
  const fx = g.commanderEffects(c);
  assert.ok(Math.abs(fx.wall_attack - 0.1) < 1e-9 && Math.abs(fx.wall_cut - 0.1) < 1e-9, JSON.stringify(fx));
  p.castle.resources.gold = 100;
  assert.equal(act(rules, p, { action: "retrain_commander", commander: 1 }, T0).error, "Not enough gold.");
  p.castle.resources.gold = 1000;
  const out = act(rules, p, { action: "retrain_commander", commander: 1 }, T0);
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.armoury.commanders[0].skills, {});
  assert.equal(out.state.castle.resources.gold, 400);
});

test("Drillmaster earns more xp", () => {
  const p = newPlayer(rules, world, "Lord", T0);
  const s = act(rules, p, { action: "state" }, T0).state;
  const c = s.castle.armoury.commanders[0];
  c.level = 10;
  c.skills = { brawler: 3, drillmaster: 1 };
  const castle = { armoury: s.castle.armoury } as never;
  assert.equal(g.addXp(castle, 1, 10)?.xp, 12);
});
