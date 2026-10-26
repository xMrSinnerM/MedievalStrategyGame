// Achievements and titles (server/rules/achievements.ts), the claim_achievement
// and set_title orders, and the wins against players they count.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { measure, note, score, shown, titleText, type AchievementRules } from "../rules/achievements.ts";
import { act, fightRaid, newPlayer, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const achievements: AchievementRules = json("data/achievements.json");
const pvp: PvpRules = json("data/pvp.json");
const world: World = json("server/world/world.json");
const T0 = 1_000_000;
const MEASURES = ["levels", "keep", "story", "streak", "research", "commander", "soldiers"];
const STATS = ["trained", "spent", "barons", "looted", "pvp_won", "pvp_held"];

test("every achievement has three rising tiers, a title for each, and nothing bought", () => {
  assert.equal(achievements.list.length, 13);
  assert.equal(achievements.rewards.length, 3);
  assert.equal(new Set(achievements.list.map((a) => a.id)).size, achievements.list.length, "ids are unique");
  for (const a of achievements.list) {
    assert.match(a.id, /^[a-z_]+$/, a.id);
    assert.equal(a.needs.length, 3, a.id);
    assert.equal(a.titles.length, 3, a.id);
    assert.ok(a.needs[0] < a.needs[1] && a.needs[1] < a.needs[2], a.id);
    assert.ok(MEASURES.includes(a.measure) || (a.measure.startsWith("stat:") && STATS.includes(a.measure.slice(5))), a.id);
  }
  assert.ok(achievements.list.find((a) => a.id === "keep")!.needs[2] <= rules.buildings.maxLevel("keep", 5), "the keep's top tier can be reached");
  for (const r of achievements.rewards) for (const k of Object.keys(r.resources ?? {})) assert.ok(rules.buildings.resources.includes(k));
  assert.equal(shown(achievements, false).length, 11);
  assert.equal(titleText(achievements, "barons:2"), "Baron-Breaker");
  for (const bad of ["barons:0", "barons:4", "nope:1", "barons", 7, null]) assert.equal(titleText(achievements, bad), "");
});

test("tiers are earned as the castle grows, claimed once each, and stay earned", () => {
  let p = newPlayer(rules, world, "Valentin", T0);
  const ctx = { achievements };
  let out = act(rules, p, { action: "claim_achievement", id: "keep" }, T0 + 1, ctx);
  assert.equal(out.error, "You haven't earned that yet.");
  assert.equal(act(rules, p, { action: "claim_achievement", id: "nope" }, T0, ctx).error, "There's no such achievement.");
  assert.equal(act(rules, p, { action: "claim_achievement", id: "keep" }, T0, {}).error, "Unknown order.");
  p = structuredClone(out.state);
  p.castle.buildings.find((b) => b.type === "keep")!.level = 4;
  p.castle.troops = { spearman: 60 };
  out = act(rules, p, { action: "state" }, T0 + 2, ctx);
  assert.deepEqual(out.state.castle.achievements.tiers, { keep: 2, garrison: 1 }, "any request notes what was reached");
  assert.equal(score(CastleState.fromDict(rules.buildings, out.state.castle), achievements), 45);
  const wood = out.state.castle.resources.wood;
  out = act(rules, out.state, { action: "claim_achievement", id: "keep" }, T0 + 2, ctx);
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.wood - wood), 300, "bronze's reward");
  out = act(rules, out.state, { action: "claim_achievement", id: "keep" }, T0 + 2, ctx);
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.gold - p.castle.resources.gold), 300, "silver's gold");
  assert.equal(act(rules, out.state, { action: "claim_achievement", id: "keep" }, T0 + 2, ctx).error, "You already have that reward.");
  // The soldiers leave: the tier stays earned.
  const gone = structuredClone(out.state);
  gone.castle.troops = {};
  out = act(rules, gone, { action: "claim_achievement", id: "garrison" }, T0 + 3, ctx);
  assert.equal(out.error, "");
  assert.equal(out.state.castle.achievements.tiers.garrison, 1);
});

test("an earned title can be shown and taken off", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  const ctx = { achievements };
  assert.equal(act(rules, p, { action: "set_title", title: "keep:1" }, T0, ctx).error, "You haven't earned that title yet.");
  assert.equal(act(rules, p, { action: "set_title", title: "keep:9" }, T0, ctx).error, "There's no such title.");
  assert.equal(act(rules, p, { action: "set_title", title: { evil: true } }, T0, ctx).error, "There's no such title.");
  p.castle.buildings.find((b) => b.type === "keep")!.level = 2;
  let out = act(rules, p, { action: "set_title", title: "keep:1" }, T0, ctx);
  assert.equal(out.error, "", "a tier reached in this very request counts");
  assert.equal(out.state.castle.achievements.title, "keep:1");
  out = act(rules, out.state, { action: "set_title", title: "" }, T0, ctx);
  assert.equal(out.state.castle.achievements.title, "");
});

test("wins and held-off attacks between players count", () => {
  const victim = newPlayer(rules, world, "Victim", T0, world.spots[2], pvp);
  const raid: Raid = { id: 7, attacker_name: "Raider", defender_name: "Victim", army: { spearman: 200, archer: 100 },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  victim.castle.troops = { spearman: 5 };
  const won = fightRaid(rules, pvp, victim, raid);
  assert.equal(won.attackerReport.winner, "a");
  assert.equal(won.defender.castle.stats.pvp_held, 0);
  victim.castle.troops = { spearman: 500, archer: 200 };
  const held = fightRaid(rules, pvp, victim, { ...raid, army: { spearman: 10 } });
  assert.equal(held.defender.castle.stats.pvp_held, 1, "the defender counts an attack held off");
  const me = newPlayer(rules, world, "Raider", T0, world.spots[1], pvp);
  const home = act(rules, me, { action: "state" }, T0 + 1300,
    { achievements, homecomings: [{ ...raid, state: "home", survivors: won.survivors, loot: won.loot, won: true }] });
  assert.equal(home.state.castle.stats.pvp_won, 1, "the attacker counts the win when the army is home");
  assert.equal(home.state.castle.achievements.tiers.conqueror, 1);
  const lost = act(rules, me, { action: "state" }, T0 + 1300, { homecomings: [{ ...raid, survivors: {}, loot: {} }] });
  assert.equal(lost.state.castle.stats.pvp_won, 0, "a lost battle doesn't");
});

test("old castles have earned nothing, and the measures read the castle", () => {
  const p = newPlayer(rules, world, "Old", T0);
  const data = structuredClone(p.castle) as unknown as Record<string, unknown>;
  delete data.achievements;
  (data.stats as Record<string, unknown>).pvp_won = undefined;
  const castle = CastleState.fromDict(rules.buildings, data);
  assert.deepEqual(castle.achievements, { tiers: {}, claimed: {}, title: "" });
  assert.equal(castle.stats.pvp_won, 0);
  castle.research = { masonry: 3, forestry: 2 };
  castle.quests.story = 12;
  const byId = (id: string) => achievements.list.find((a) => a.id === id)!;
  assert.equal(measure(castle, byId("scholar")), 5);
  assert.equal(measure(castle, byId("story")), 12);
  assert.deepEqual(note(castle, achievements, true).sort(), [["scholar", 1], ["story", 1]]);
});
