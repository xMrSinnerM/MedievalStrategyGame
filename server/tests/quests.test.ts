// Quests and daily tasks (server/rules/quests.ts) and the claim_quest order.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { claimQuest, cofferReward, currentStreak, DAY, dailyProgress, progress, rollDay, type QuestRules } from "../rules/quests.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const quests: QuestRules = json("data/quests.json");
const world: World = json("server/world/world.json");
const D0 = 20000 * DAY;

test("every story quest can be done and gives something real", () => {
  const b = rules.buildings;
  assert.equal(quests.story.length, 30);
  for (const q of quests.story) {
    assert.ok(q.chapter >= 0 && q.chapter < quests.chapters.length, q.title);
    const g = q.goal;
    if (g.kind === "building") {
      assert.ok(b.hasType(g.type!), q.title);
      assert.ok(g.level! <= b.maxLevel(g.type!, 5), `${q.title}: level reachable`);
      assert.ok((g.count ?? 1) <= b.maxCount(g.type!, 5), `${q.title}: count reachable`);
    } else if (g.kind === "stat") {
      assert.ok(["trained", "spent", "barons", "looted"].includes(g.stat!), q.title);
    } else if (g.kind === "production") {
      assert.ok(b.resources.includes(g.resource!), q.title);
    } else {
      assert.ok(["soldiers", "storage", "levels"].includes(g.kind), q.title);
    }
    const r = q.reward;
    assert.ok(Object.keys(r.resources ?? {}).length + Object.keys(r.troops ?? {}).length > 0, `${q.title} has a reward`);
    for (const k of Object.keys(r.resources ?? {})) assert.ok(b.resources.includes(k), `${q.title}: ${k}`);
    for (const k of Object.keys(r.troops ?? {})) assert.ok(b.hasUnit(k), `${q.title}: ${k}`);
  }
  for (const k of Object.keys(quests.daily.kinds)) assert.equal(quests.daily.kinds[k].targets.length, quests.daily.scale.length, k);
});

test("the story is claimed in order, once each, with its reward in full", () => {
  const p = newPlayer(rules, world, "Valentin", D0);
  let out = act(rules, p, { action: "claim_quest", kind: "story" }, D0 + 10, { quests });
  assert.equal(out.error, "That quest isn't done yet.");
  const cutter = out.state.castle.buildings.find((b) => b.type === "woodcutter")!;
  out = act(rules, out.state, { action: "upgrade", id: cutter.id }, D0 + 20, { quests });
  assert.equal(out.error, "");
  const before = act(rules, out.state, { action: "state" }, D0 + 3600, { quests }).state.castle;
  out = act(rules, out.state, { action: "claim_quest", kind: "story" }, D0 + 3600, { quests });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.quests.story, 1);
  assert.equal(Math.round(out.state.castle.resources.wood - before.resources.wood), 150);
  assert.equal(Math.round(out.state.castle.resources.stone - before.resources.stone), 100);
  out = act(rules, out.state, { action: "claim_quest", kind: "story" }, D0 + 3601, { quests });
  assert.equal(out.error, "That quest isn't done yet.", "the next quest wants a quarry");
  assert.equal(act(rules, p, { action: "claim_quest", kind: "story" }, D0, {}).error, "Unknown order.");
  assert.equal(act(rules, p, { action: "claim_quest", kind: "nope" }, D0, { quests }).error, "There's no such quest.");
});

test("rewards go past the storage cap", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", D0);
  castle.resources.wood = castle.storageCapacity();
  castle.quests.story = 0;
  castle.buildings.find((b) => b.type === "woodcutter")!.level = 2;
  assert.equal(claimQuest(castle, quests, "story", 0, D0), "");
  assert.equal(castle.resources.wood, castle.storageCapacity() + 150);
});

test("daily tasks: a new set each day, counted from the start of the day", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "Valentin's Castle", "player", D0);
  assert.ok(rollDay(castle, quests, D0 + 5));
  assert.ok(!rollDay(castle, quests, D0 + DAY - 1), "same day");
  assert.deepEqual([...castle.quests.picks].sort(), ["levels", "spent"], "no barracks: no soldier tasks");
  const spent = castle.quests.picks.indexOf("spent");
  assert.deepEqual(dailyProgress(castle, quests, spent), [0, 1500]);
  castle.stats.spent += 1499.5;
  assert.equal(claimQuest(castle, quests, "daily", spent, D0 + 10), "That task isn't done yet.");
  castle.stats.spent += 0.5;
  const gold = castle.resources.gold;
  assert.equal(claimQuest(castle, quests, "daily", spent, D0 + 10), "");
  assert.equal(castle.resources.gold, gold + 60);
  assert.equal(claimQuest(castle, quests, "daily", spent, D0 + 10), "You already have that reward.");
  assert.equal(claimQuest(castle, quests, "daily", 5, D0 + 10), "There's no such task.");
  assert.equal(claimQuest(castle, quests, "chest", 0, D0 + 10), "Finish today's tasks first.");
  // Tomorrow's tasks start from scratch, with a barracks now.
  castle.buildings.push({ id: 99, type: "barracks", level: 1, cell: [0, 0], target: 0, finish: 0 });
  assert.ok(rollDay(castle, quests, D0 + DAY));
  assert.equal(castle.quests.picks.length, 3);
  assert.deepEqual(castle.quests.claimed, []);
  for (let i = 0; i < 3; i++) assert.equal(dailyProgress(castle, quests, i)[0], 0);
});

test("the coffer grows with a streak of days, and a missed day starts it over", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", D0);
  const finishDay = (t: number) => {
    rollDay(castle, quests, t);
    for (const k of castle.quests.picks) {
      if (k === "levels") castle.buildings.find((b) => b.type === "farm")!.level += 10;
      else (castle.stats as unknown as Record<string, number>)[k] += 1e6;
    }
    castle.quests.picks.forEach((_, i) => assert.equal(claimQuest(castle, quests, "daily", i, t), ""));
    const food = castle.resources.food;
    const swords = castle.troops.swordsman ?? 0;
    assert.equal(claimQuest(castle, quests, "chest", 0, t), "");
    assert.equal(claimQuest(castle, quests, "chest", 0, t), "You already opened today's coffer.");
    return [castle.resources.food - food, (castle.troops.swordsman ?? 0) - swords];
  };
  assert.deepEqual(finishDay(D0), [150, 0]);
  assert.deepEqual(finishDay(D0 + DAY), [188, 0], "150 x 1.25, rounded");
  assert.equal(currentStreak(castle), 2);
  for (let d = 2; d < 6; d++) finishDay(D0 + d * DAY);
  assert.deepEqual(finishDay(D0 + 6 * DAY), [375, 4], "seventh day: 150 x 2.5 and swordsmen");
  assert.deepEqual(finishDay(D0 + 7 * DAY), [375, 4], "the streak stays at its best");
  rollDay(castle, quests, D0 + 9 * DAY);
  assert.equal(currentStreak(castle), 0, "a day was missed");
  assert.deepEqual(finishDay(D0 + 9 * DAY), [150, 0]);
  // A bigger keep when the day begins means bigger tasks and rewards.
  assert.deepEqual(cofferReward(quests, 3, 1).resources, { wood: 750, stone: 750, food: 750, gold: 400 });
});

test("lifetime stats: soldiers trained, resources spent, barons beaten, loot brought home", () => {
  const p = newPlayer(rules, world, "Valentin", D0);
  p.castle.buildings.push({ id: 99, type: "barracks", level: 1, cell: [0, 0], target: 0, finish: 0 });
  let out = act(rules, p, { action: "recruit", unit: "spearman", amount: 5 }, D0, { quests });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.stats.spent, 5 * 22);
  out = act(rules, out.state, { action: "cancel_training", index: 0 }, D0 + 1, { quests });
  assert.equal(out.state.castle.stats.spent, 5 * 22 * 0.25, "a cancelled batch gives back 75%");
  out = act(rules, out.state, { action: "recruit", unit: "spearman", amount: 3 }, D0 + 2, { quests });
  out = act(rules, out.state, { action: "state" }, D0 + 3600, { quests });
  assert.equal(out.state.castle.stats.trained, 3);
  out = act(rules, out.state, { action: "state" }, D0 + 3601,
    { quests, homecomings: [{ back: D0 + 3600, survivors: { spearman: 2 }, loot: { wood: 300, gold: 50 } }] });
  assert.equal(out.state.castle.stats.looted, 350);
  const camp = out.state.camps[0];
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { spearman: 5 } }, D0 + 3602, { quests });
  assert.equal(out.error, "");
  const march = out.state.marches[0];
  out = act(rules, out.state, { action: "state" }, march.back + 1, { quests });
  assert.equal(out.state.castle.stats.barons, out.reports[0].winner === "a" ? 1 : 0);
  if (out.reports[0].winner === "a") {
    const loot = Object.values(out.reports[0].spoils).reduce((a, b) => a + b, 0);
    assert.equal(out.state.castle.stats.looted, 350 + loot);
  }
  assert.equal(progress(CastleState.fromDict(rules.buildings, out.state.castle), { kind: "stat", stat: "trained", amount: 3 })[0], 3);
});
