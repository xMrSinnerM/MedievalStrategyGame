// Replays fixtures.json (written by tests/dump_server_fixtures.gd from the
// game's own rules) through the server's TypeScript rules and checks that
// every result matches. Run from the repository root:
//   node --test server/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { attackCamp, isReady, type CampData } from "../rules/baron_camp.ts";
import { autoWaves, checkTools, fight, odds, siege, siegeOdds, split } from "../rules/battle.ts";
import { CastleState } from "../rules/castle_state.ts";
import { makeRules } from "../rules/load.ts";
import { deliverCarts, nearestSpot, type Cart } from "../rules/outposts.ts";
import { godotHash } from "../rules/util.ts";
import { capture } from "../rules/villages.ts";
import { claimQuest, cofferReward, cofferStreak, currentStory, dailyProgress, pickDailies, progress, type QuestRules } from "../rules/quests.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), json("data/villages.json"), json("data/capitals.json"), json("data/fortresses.json"));
const fixtures = json("server/tests/fixtures.json");
const T0 = 1_000_000;
const quests: QuestRules = json("data/quests.json");

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
    let castle = CastleState.createNew(rules.buildings, run.id, run.name, "player", run.t0);
    run.steps.forEach((step: any, i: number) => {
      const where = `${run.id} step ${i} (${step.op})`;
      switch (step.op) {
        case "advance":
          castle.advanceTo(step.t);
          break;
        case "load":
          castle = CastleState.fromDict(rules.buildings, step.data);
          break;
        case "research":
          assert.equal(castle.startResearch(step.study, step.t), step.result, where);
          break;
        case "cancel_research":
          assert.equal(castle.cancelResearch(step.t), step.result, where);
          break;
        case "heal": {
          const before = { ...castle.troops };
          for (const unit of Object.keys(step.lost)) castle.troops[unit] -= step.lost[unit];
          same(castle.heal(before), step.healed, `${where} healed`);
          break;
        }
        case "research_checks":
          for (const study of Object.keys(step.research)) {
            assert.equal(castle.checkResearch(study), step.research[study], `${where} research ${study}`);
            const open = castle.studyLevel(study) < rules.buildings.studyMaxLevel(study);
            same({ time: open ? castle.researchTime(study) : 0, cost: rules.buildings.studyCost(study, castle.studyLevel(study) + 1) },
              step[study], `${where} study ${study}`);
          }
          for (const type of Object.keys(step.build)) assert.equal(castle.checkBuild(type), step.build[type], `${where} build ${type}`);
          for (const unit of Object.keys(step.recruit)) {
            same([castle.checkRecruit(unit, 10), castle.unitTime(unit), castle.unitUpkeep(unit)], step.recruit[unit], `${where} recruit ${unit}`);
          }
          for (const tool of Object.keys(step.craft)) same([castle.checkCraft(tool, 10), castle.toolTime(tool)], step.craft[tool], `${where} craft ${tool}`);
          same({ slots: castle.defenceSlots(), hidden: castle.hidden(), march: castle.marchFactor(), storage: castle.storageCapacity(),
            rates: castle.netPerHour(), left: castle.studying ? Math.max(castle.studying.finish - step.t, 0) : 0,
            attack: castle.researchEffects("attack"), defence: castle.researchEffects("defence"),
            castellan: rules.gear.castellanEffects(castle), lead: rules.gear.checkLead(castle, 0, step.t) }, step.numbers, `${where} numbers`);
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
        case "craft":
          assert.equal(castle.craft(step.tool, step.amount, step.t), step.result, where);
          break;
        case "cancel_crafting":
          assert.equal(castle.cancelCrafting(step.index, step.t), step.result, where);
          break;
        case "set_tools":
          castle.tools[step.gift] = (castle.tools[step.gift] ?? 0) + step.n;
          assert.equal(castle.setDefenceTools(step.tools), step.result, where);
          if (step.lost) castle.loseDefenceTools(step.lost);
          break;
        case "move":
          assert.equal(castle.move(step.id, step.cell), step.result, where);
          break;
        case "grant":
          castle.resources[step.resource] += step.amount;
          break;
        case "quest":
          assert.equal(claimQuest(castle, quests, step.kind, step.index, step.t), step.result, where);
          break;
        case "stats":
          castle.stats.barons += step.barons;
          castle.stats.looted += step.looted;
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
          for (const tool of Object.keys(step.craft)) assert.equal(castle.checkCraft(tool, 10), step.craft[tool], `${where} craft ${tool}`);
          {
            const story = currentStory(castle, quests);
            same(story ? progress(castle, story.goal) : [], step.story, `${where} story`);
            same(castle.quests.picks.map((_, i) => dailyProgress(castle, quests, i)), step.daily, `${where} daily`);
            same(cofferReward(quests, castle.quests.keep, cofferStreak(castle, quests)), step.coffer, `${where} coffer`);
            same(quests.story.map((q) => progress(castle, q.goal)), step.goals, `${where} goals`);
            same([castle.publicOrder(), castle.netPerHour()], step.order, `${where} public order`);
          }
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

test("siege waves", () => {
  assert.ok(fixtures.sieges.length > 0);
  fixtures.sieges.forEach((c: any, i: number) => {
    same(siege(rules.buildings, c.waves, c.defenders, c.layout, c.seed, c.wall, c.tools), c.result, `siege ${i}`);
    same(siegeOdds(rules.buildings, c.waves, c.defenders, c.layout, c.seed, c.wall, c.tools), c.odds, `siege ${i} odds`);
    for (const side of ["attack", "defence"]) {
      const r = checkTools(rules.buildings, c.tools.a ?? {}, side, c.checks[side].slots, c.stock);
      assert.equal(typeof r === "string" ? r : "", c.checks[side].result, `siege ${i} ${side} tools`);
    }
    same(autoWaves(c.army), c.auto, `siege ${i} auto waves`);
    same(split(c.defenders, c.layout, ["left", "right", "courtyard", "front"]), c.split, `siege ${i} split`);
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

test("fortress rules by level", () => {
  const r = rules.barons.forCamp({ fortress: true });
  assert.notEqual(r, rules.barons);
  for (const b of fixtures.fortresses) {
    same({ garrison: r.garrison(b.level), palisade: r.palisade(b.level), loot: r.loot(b.level),
      defeats_needed: r.defeatsNeeded(b.level), rebuild_time: r.rebuildTime(b.level) },
      { garrison: b.garrison, palisade: b.palisade, loot: b.loot, defeats_needed: b.defeats_needed, rebuild_time: b.rebuild_time },
      `fortress level ${b.level}`);
  }
});

test("daily task picks", () => {
  assert.ok(fixtures.dailies.length > 0);
  for (const c of fixtures.dailies) {
    const castle = CastleState.createNew(rules.buildings, "c", c.name, "player", 0);
    same(pickDailies(castle, quests, c.day), c.none, `${c.name} day ${c.day}`);
    castle.buildings.push({ id: 99, type: "barracks", level: 1, cell: [0, 0], target: 0, finish: 0 });
    same(pickDailies(castle, quests, c.day), c.barracks, `${c.name} day ${c.day} with a barracks`);
  }
});

test("camp attacks", () => {
  fixtures.camp_attacks.forEach((run: any, k: number) => {
    const camp: CampData = structuredClone(run.start);
    run.attacks.forEach((a: any, i: number) => {
      const where = `camp ${k} attack ${i}`;
      assert.equal(isReady(camp, a.t), a.ready, where);
      if (a.ready) same(attackCamp(camp, rules.barons, rules.buildings, a.army, a.seed, a.t, undefined, {}, a.lead), a.result, where);
      same(camp, a.camp, where);
    });
  });
});

test("gear drops", () => {
  assert.ok(fixtures.drops.length > 0);
  fixtures.drops.forEach((d: any, i: number) => {
    same(rules.gear.rollDrop(d.level, d.seed) ?? {}, d.item, `drop ${i} (level ${d.level})`);
  });
});

test("commanders and gear", () => {
  const run = fixtures.armoury;
  const g = rules.gear;
  const castle = CastleState.createNew(rules.buildings, "g", "Gear Castle", "player", T0);
  for (const b of castle.buildings) if (b.type === "keep") b.level = 5;
  g.sync(castle);
  castle.armoury.commanders[1].away_until = T0 + 100;
  for (const d of run.drops) {
    if (Object.keys(d).length > 0) g.give(castle, structuredClone(d));
  }
  run.ops.forEach((op: any, i: number) => {
    const where = `op ${i} (${op.kind})`;
    if (op.kind === "equip") assert.equal(g.equip(castle, op.who, op.item, op.t), op.result, where);
    else if (op.kind === "unequip") assert.equal(g.unequip(castle, op.who, op.slot, op.t), op.result, where);
    else if (op.kind === "sell") assert.equal(g.sell(castle, op.item), op.result, where);
    else same(g.addXp(castle, op.id, op.xp) ?? {}, op.result, where);
  });
  same(castle.toDict(), run.castle, "castle");
  same(castle.armoury.commanders.map((c) => g.effects(c.gear, c.level)), run.fx, "commander effects");
  same(g.castellanEffects(castle), run.castellan, "castellan effects");
  same([0, 1, 2, 3, 9].map((id) => g.checkLead(castle, id, T0 + 50) ?? "none"), run.leads, "leads");
  const levels: number[] = [];
  for (let x = 0; x < 320; x += 7) levels.push(g.levelFor(x));
  same(levels, run.levels, "levels");
});

test("outposts", () => {
  const run = fixtures.outpost;
  const o = rules.outposts;
  const main = CastleState.createNew(rules.buildings, "c", "Main Castle", "player", run.t0);
  const checks: Record<string, string> = { too_low: o.checkFound(main, false, "wood", [1, 1]) };
  for (const b of main.buildings) if (b.type === "keep") b.level = o.keepNeeded;
  checks.poor = o.checkFound(main, false, "wood", [1, 1]);
  for (const r of Object.keys(main.resources)) main.resources[r] = 9000;
  checks.has = o.checkFound(main, true, "wood", [1, 1]);
  checks.region = o.checkFound(main, false, "silk", [1, 1]);
  checks.spot = o.checkFound(main, false, "stone", null);
  checks.ok = o.checkFound(main, false, "stone", [1, 1]);
  same(checks, run.checks, "checks");
  const outpost = o.found(main, run.region, run.t0);
  let carts: Cart[] = [];
  let nextCart = 1;
  run.steps.forEach((step: any, i: number) => {
    const where = `outpost step ${i} (${step.op})`;
    switch (step.op) {
      case "advance":
        carts = deliverCarts(main, outpost, carts, step.t);
        main.advanceTo(step.t);
        outpost.advanceTo(step.t);
        break;
      case "place":
        assert.equal(outpost.place(step.type, step.cell, step.t), step.result, where);
        break;
      case "upgrade":
        assert.equal(outpost.upgrade(step.id, step.t), step.result, where);
        break;
      case "grant":
        outpost.resources[step.resource] += step.amount;
        break;
      case "carts": {
        const from = step.home ? main : outpost;
        assert.equal(o.checkCarts(from, step.load), step.result, where);
        assert.equal(o.cartCapacity(from), step.cap, `${where} capacity`);
        if (step.result === "") {
          for (const r of Object.keys(step.load)) from.resources[r] -= step.load[r];
          carts.push({ id: nextCart++, to: step.home ? "outpost" : "home", resources: step.load, depart: step.t,
            arrive: step.t + step.travel });
        }
        break;
      }
      case "checks":
        for (const type of Object.keys(step.build)) assert.equal(outpost.checkBuild(type), step.build[type], `${where} build ${type}`);
        for (const id of Object.keys(step.upgrade)) assert.equal(outpost.checkUpgrade(Number(id)), step.upgrade[id], `${where} upgrade ${id}`);
        break;
      default:
        assert.fail(`unknown op ${step.op}`);
    }
    same(main.toDict(), step.main, `${where} main`);
    same(outpost.toDict(), step.outpost, `${where} outpost`);
    same(carts, step.carts, `${where} carts`);
  });
  same(CastleState.fromDict(rules.buildings, run.steps.at(-1).outpost).toDict(), run.steps.at(-1).outpost, "outpost save round trip");
  for (const c of run.nearest) same(nearestSpot(run.spots, c.home, c.taken), c.spot, `nearest to ${c.home}`);
});

for (const [name, v] of [["villages", rules.villages], ["capitals", rules.capitals]] as const) test(name, () => {
  const run = fixtures[name];
  for (const l of run.levels) {
    same(v.militia(l.level), l.militia, `militia ${l.level}`);
    same(v.palisade(l.level), l.palisade, `palisade ${l.level}`);
    for (const r of Object.keys(l.yields)) same([v.yieldPerHour(r, l.level), v.storeCap(r, l.level)], l.yields[r], `yields ${r} ${l.level}`);
  }
  run.slots.forEach((row: unknown[], keep: number) =>
    same([v.slotsFor(keep), v.checkRoom(keep, 0), v.checkRoom(keep, 1), v.checkRoom(keep, 3)], row, `slots ${keep}`));
  run.payouts.forEach((p: Record<string, any>, i: number) => {
    same(v.stock(p.info, p.state, p.t), p.stock, `payout ${i} stock`);
    same(v.collect(p.info, p.state, p.t), p.collect, `payout ${i} collect`);
    same(v.peaceUntil(p.state), p.peace, `payout ${i} peace`);
  });
  run.attacks.forEach((a: Record<string, any>, i: number) => {
    const got = v.attack(rules.buildings, rules.barons, a.info, a.state, a.army, a.seed, a.t, a.waves.length > 0 ? a.waves : undefined,
      {}, a.lead);
    const { survivors, guardLeft, ...rest } = got;
    same({ ...rest, survivors, guard_left: guardLeft }, a.result, `${name} attack ${i}`);
  });
});

test("capital bonus", () => {
  for (const b of fixtures.capitals.bonus) {
    same(rules.capitals.totalBonus(b.levels, b.guilds), b.total, `bonus ${b.levels} ${b.guilds}`);
    same(rules.capitals.boost(b.levels, rules.buildings.resources, b.guilds), b.boost, `boost ${b.levels} ${b.guilds}`);
    same(rules.capitals.checkAlliance(b.levels.length), b.alliance, `alliance ${b.levels}`);
  }
});

test("capital town buildings", () => {
  const c = rules.capitals;
  const run = fixtures.capitals.town;
  for (const id of Object.keys(run.levels)) {
    run.levels[id].forEach((row: Record<string, unknown>, level: number) =>
      same({ cost: c.buildingCost(id, level), time: c.buildingTime(id, level), effect: c.buildingEffect(id, level) }, row,
        `${id} level ${level}`));
  }
  run.starts.forEach((s: Record<string, any>, i: number) => {
    same(c.buildingLevels(s.state, s.t), s.levels, `start ${i} levels`);
    same(c.underWay(s.state, s.t) ?? {}, s.under_way, `start ${i} under way`);
    same(c.startBuild(s.state, s.id, s.t), s.start, `start ${i}`);
    same(capture(s.state, "Taker", s.t), s.settled, `start ${i} captured`);
  });
});
