// Siege waves (server/rules/battle.ts siege()): walls, waves and the
// courtyard, in camp attacks and attacks on players.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { autoWaves, checkLayout, DEFAULT_LAYOUT, siege, wavesForKeep } from "../rules/battle.ts";
import { attackCamp, type CampData } from "../rules/baron_camp.ts";
import { act, fightRaid, newPlayer, spyReport, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const T0 = 1_000_000;

test("break a wall, then win the courtyard", () => {
  const r = siege(rules.buildings, [{ front: { swordsman: 200 } }, { front: { archer: 20 } }], { spearman: 60 }, DEFAULT_LAYOUT, 5, 1.5);
  assert.equal(r.winner, "a");
  assert.ok(r.walls.front.broken);
  assert.deepEqual(r.walls.front.fights[1], { wave: 1, open: true }, "the second wave walks through");
  assert.ok("winner" in r.courtyard);
  assert.equal(r.a.archer.lost, 0);
  assert.equal(Object.values(r.b).reduce((n, s) => n + s.start, 0), 60, "every defender counted once");
});

test("a wall that holds sends its attackers home", () => {
  const r = siege(rules.buildings, [{ front: { spearman: 5 } }], { spearman: 100 }, DEFAULT_LAYOUT, 3, 2.0);
  assert.equal(r.winner, "b");
  assert.equal(r.walls.front.broken, false);
  assert.deepEqual(r.courtyard, {});
  assert.deepEqual(r.walls.left.fights, []);
});

test("empty walls and courtyards fall without a fight", () => {
  const r = siege(rules.buildings, [{ left: { spearman: 5 } }], { spearman: 50 }, { left: 0, front: 100, right: 0, courtyard: 0 }, 1, 2.0);
  assert.equal(r.winner, "a");
  assert.deepEqual(r.courtyard, { open: true });
  assert.equal(r.a.spearman.lost + r.b.spearman.lost, 0);
});

test("layouts, waves and the automatic split", () => {
  assert.equal(checkLayout(DEFAULT_LAYOUT), "");
  assert.notEqual(checkLayout({ left: 50, front: 50, right: 0, courtyard: 10 }), "");
  assert.notEqual(checkLayout({ left: 50, front: 50 }), "");
  assert.notEqual(checkLayout({ left: 50.5, front: 49.5, right: 0, courtyard: 0 }), "");
  assert.deepEqual(autoWaves({ spearman: 10 }), [{ left: { spearman: 3 }, right: { spearman: 3 }, front: { spearman: 4 } }]);
  assert.deepEqual([1, 2, 3, 4, 5].map(wavesForKeep), [1, 2, 2, 3, 3]);
});

test("camp attacks are sieges and report their walls", () => {
  const camp: CampData = { id: "baron_1", name: "Camp", position: [0, 0], level: 1, defeats: 0, rebuilt_at: 0 };
  const r = attackCamp(camp, rules.barons, rules.buildings, { swordsman: 60 }, 1, 100);
  assert.equal(r.winner, "a");
  assert.deepEqual(Object.keys(r.walls), ["left", "front", "right"]);
  assert.equal(r.waves, 1);
});

test("attacks can choose their waves, as many as the keep allows", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  p.castle.troops = { spearman: 50, archer: 20 };
  const camp = p.camps[0].id;
  const two = [{ left: { spearman: 10 } }, { front: { archer: 5 } }];
  assert.equal(act(rules, p, { action: "attack", camp, waves: two }, T0).error, "Upgrade your keep to send more than one wave.");
  const one = [{ left: { spearman: 10 }, front: { spearman: 20, archer: 5 }, right: {} }];
  const out = act(rules, p, { action: "attack", camp, waves: one }, T0);
  assert.equal(out.error, "");
  assert.deepEqual(out.state.marches[0].army, { spearman: 30, archer: 5 });
  assert.deepEqual(out.state.marches[0].waves, [{ left: { spearman: 10 }, front: { spearman: 20, archer: 5 } }]);
  assert.equal(out.state.castle.troops.spearman, 20);
  assert.equal(act(rules, p, { action: "attack", camp, waves: [{ left: { spearman: 99 } }] }, T0).error,
    "Your garrison doesn't have that many soldiers.");
  assert.equal(act(rules, p, { action: "attack", camp, waves: [{ middle: { spearman: 1 } }] }, T0).error, "Bad waves.");
  assert.equal(act(rules, p, { action: "attack", camp, waves: [{ left: { dragon: 1 } }] }, T0).error, "Unknown unit.");
  // The march fights in those waves when it arrives.
  const later = act(rules, out.state, { action: "state" }, out.state.marches[0].arrive + 1);
  const report = later.reports[0];
  assert.equal(report.walls?.right.fights.length, 0, "nobody came at the right wall");
  assert.ok((report.walls?.left.fights.length ?? 0) > 0);
});

test("players set where their garrison stands, and attacks and spies see it", () => {
  const p = newPlayer(rules, world, "Victim", T0, world.spots[2], pvp);
  assert.deepEqual(p.castle.layout, DEFAULT_LAYOUT);
  assert.notEqual(act(rules, p, { action: "set_layout", layout: { left: 50, front: 50, right: 50, courtyard: 0 } }, T0).error, "");
  const set = act(rules, p, { action: "set_layout", layout: { left: 0, front: 100, right: 0, courtyard: 0 } }, T0);
  assert.equal(set.error, "");
  const victim = { ...set.state, castle: { ...set.state.castle, troops: { spearman: 200 } } };
  assert.deepEqual(spyReport(rules, pvp, victim, T0).layout, { left: 0, front: 100, right: 0, courtyard: 0 });
  // Nobody guards the left wall or the courtyard: a handful walks in there.
  const raid: Raid = { id: 3, attacker_name: "Raider", defender_name: "Victim", army: { spearman: 5 },
    waves: [{ left: { spearman: 5 } }], from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200,
    state: "out", survivors: {}, loot: {} };
  const out = fightRaid(rules, pvp, victim, raid);
  assert.equal(out.attackerReport.winner, "a");
  assert.deepEqual(out.attackerReport.courtyard, { open: true });
  assert.equal(out.defender.castle.troops.spearman, 200);
});
