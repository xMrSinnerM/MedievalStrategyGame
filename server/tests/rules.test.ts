// Replays fixtures.json (written by tests/dump_server_fixtures.gd from the
// game's own rules) through the server's TypeScript rules and checks that
// every result matches. Run from the repository root:
//   node --test server/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { attackCamp, isReady, type CampData } from "../rules/baron_camp.ts";
import { fight, odds } from "../rules/battle.ts";
import { CastleState } from "../rules/castle_state.ts";
import { makeRules } from "../rules/load.ts";
import { godotHash } from "../rules/util.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const fixtures = json("server/tests/fixtures.json");

/** Deep equality where numbers may differ by a hair (pow() in C and in JS). */
function same(actual: unknown, expected: unknown, path = "$"): void {
  if (typeof expected === "number") {
    assert.equal(typeof actual, "number", `${path}: expected a number, got ${JSON.stringify(actual)}`);
    const a = actual as number;
    const ok = a === expected || Math.abs(a - expected) <= 1e-7 * Math.max(1, Math.abs(expected));
    assert.ok(ok, `${path}: expected ${expected}, got ${a}`);
    return;
  }
  if (Array.isArray(expected)) {
    assert.ok(Array.isArray(actual), `${path}: expected an array`);
    const arr = actual as unknown[];
    assert.equal(arr.length, expected.length, `${path}: expected ${expected.length} items, got ${arr.length}`);
    expected.forEach((e, i) => same(arr[i], e, `${path}[${i}]`));
    return;
  }
  if (expected !== null && typeof expected === "object") {
    assert.ok(actual !== null && typeof actual === "object", `${path}: expected an object`);
    const obj = actual as Record<string, unknown>;
    const keys = Object.keys(expected as object).sort();
    assert.deepEqual(Object.keys(obj).sort(), keys, `${path}: keys differ`);
    for (const k of keys) same(obj[k], (expected as Record<string, unknown>)[k], `${path}.${k}`);
    return;
  }
  assert.equal(actual, expected, path);
}

test("Godot's random numbers", () => {
  for (const [s, h] of Object.entries(fixtures.hashes)) assert.equal(godotHash(s), h, `hash of "${s}"`);
});

for (const run of fixtures.castles) {
  test(`castle orders: ${run.id}`, () => {
    const castle = CastleState.createNew(rules.buildings, run.id, run.name, "player", run.t0);
    run.steps.forEach((step: any, i: number) => {
      const where = `${run.id} step ${i} (${step.op})`;
      switch (step.op) {
        case "advance":
          castle.advanceTo(step.t);
          break;
        case "place":
          assert.equal(castle.place(step.type, step.cell, step.t), step.result, where);
          break;
        case "upgrade":
          assert.equal(castle.upgrade(step.id, step.t), step.result, where);
          break;
        case "cancel":
          assert.equal(castle.cancel(step.id, step.t), step.result, where);
          break;
        case "recruit":
          assert.equal(castle.recruit(step.unit, step.amount, step.t), step.result, where);
          break;
        case "cancel_training":
          assert.equal(castle.cancelTraining(step.index, step.t), step.result, where);
          break;
        case "move":
          assert.equal(castle.move(step.id, step.cell), step.result, where);
          break;
        case "grant":
          castle.resources[step.resource] += step.amount;
          break;
        case "soldiers": {
          const group = step.field ? castle.field : castle.troops;
          group[step.unit] = (group[step.unit] ?? 0) + step.amount;
          break;
        }
        case "checks":
          for (const type of Object.keys(step.build)) assert.equal(castle.checkBuild(type), step.build[type], `${where} build ${type}`);
          for (const id of Object.keys(step.upgrade)) assert.equal(castle.checkUpgrade(Number(id)), step.upgrade[id], `${where} upgrade ${id}`);
          for (const unit of Object.keys(step.recruit)) assert.equal(castle.checkRecruit(unit, 10), step.recruit[unit], `${where} recruit ${unit}`);
          break;
        default:
          assert.fail(`unknown op ${step.op}`);
      }
      same(castle.toDict(), step.state, where);
    });
  });
}

test("castle state survives a save round trip", () => {
  const last = fixtures.castles[0].steps.at(-1).state;
  same(CastleState.fromDict(rules.buildings, last).toDict(), last);
});

test("battles", () => {
  fixtures.battles.forEach((c: any, i: number) => {
    same(fight(rules.buildings, c.a, c.b, c.seed, c.wall), c.result, `battle ${i}`);
    same(odds(rules.buildings, c.a, c.b, c.seed, c.wall), c.odds, `battle ${i} odds`);
  });
});

test("baron rules by level", () => {
  for (const b of fixtures.barons) {
    const r = rules.barons;
    same({ garrison: r.garrison(b.level), palisade: r.palisade(b.level), loot: r.loot(b.level),
      defeats_needed: r.defeatsNeeded(b.level), rebuild_time: r.rebuildTime(b.level), march_time: r.marchTime(b.level * 37.5) },
      { garrison: b.garrison, palisade: b.palisade, loot: b.loot, defeats_needed: b.defeats_needed,
        rebuild_time: b.rebuild_time, march_time: b.march_time }, `level ${b.level}`);
  }
});

test("camp attacks", () => {
  fixtures.camp_attacks.forEach((run: any, k: number) => {
    const camp: CampData = structuredClone(run.start);
    run.attacks.forEach((a: any, i: number) => {
      const where = `camp ${k} attack ${i}`;
      assert.equal(isReady(camp, a.t), a.ready, where);
      if (a.ready) same(attackCamp(camp, rules.barons, rules.buildings, a.army, a.seed, a.t), a.result, where);
      same(camp, a.camp, where);
    });
  });
});
