// The Royal Gift (server/rules/login.ts) and the claim_login order.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { claimLogin, currentStreak, DAY, loginReward, weeksKept, type LoginRules } from "../rules/login.ts";
import { measure, type AchievementRules } from "../rules/achievements.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const login: LoginRules = json("data/login.json");
const achievements: AchievementRules = json("data/achievements.json");
const world: World = json("server/world/world.json");
const D0 = 20000 * DAY;

test("a week of gifts with real resources and soldiers on day 7", () => {
  assert.equal(login.days.length, 7);
  for (const d of login.days) {
    for (const r of Object.keys(d.resources ?? {})) assert.ok(rules.buildings.resources.includes(r), r);
    for (const u of Object.keys(d.troops ?? {})) assert.ok(rules.buildings.hasUnit(u), u);
  }
  assert.ok(Object.keys(login.days[6].troops ?? {}).length > 0);
});

test("a streak walks through the week, keeps a bonus for full weeks, and a missed day starts over", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", D0);
  castle.resources.wood = castle.storageCapacity();
  assert.equal(claimLogin(castle, login, D0 + 100), "");
  assert.equal(castle.resources.wood, castle.storageCapacity() + 150, "day 1 in full, past the cap");
  assert.equal(claimLogin(castle, login, D0 + 200), "You already have today's gift. Come back tomorrow.");
  const got: [number, number][] = [];
  for (let day = 1; day <= 8; day++) {
    const gold = castle.resources.gold;
    const swords = castle.troops.swordsman ?? 0;
    assert.equal(claimLogin(castle, login, D0 + day * DAY + 50), "");
    got.push([Math.round(castle.resources.gold - gold), (castle.troops.swordsman ?? 0) - swords]);
  }
  assert.deepEqual(got[0], [50, 0]);
  assert.deepEqual(got[5], [200, 5], "day 7 brings soldiers");
  assert.deepEqual(got[7], [55, 0], "day 2 of the second week is a tenth bigger");
  assert.deepEqual(castle.login, { last: 20008, streak: 9, total: 9 });
  assert.equal(currentStreak(castle, D0 + 9 * DAY), 9);
  assert.equal(currentStreak(castle, D0 + 10 * DAY), 0);
  assert.equal(claimLogin(castle, login, D0 + 10 * DAY), "");
  assert.deepEqual(castle.login, { last: 20010, streak: 1, total: 10 });
  assert.equal(measure(castle, achievements.list.find((a) => a.id === "faithful")!), 10);
  assert.equal(loginReward(login, 0, 3).resources!.wood, 750, "keep 3 gets five times as much");
  assert.equal(weeksKept(login, 1000), login.max_weeks);
});

test("the gift log is saved, and old castles have taken none", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", D0);
  claimLogin(castle, login, D0);
  const saved = CastleState.fromDict(rules.buildings, JSON.parse(JSON.stringify(castle.toDict())));
  assert.deepEqual(saved.login, castle.login);
  const old = castle.toDict() as unknown as Record<string, unknown>;
  delete old.login;
  assert.equal(CastleState.fromDict(rules.buildings, old as never).login.last, -1);
});

test("the claim_login order gives today's gift once", () => {
  const p = newPlayer(rules, world, "Valentin", D0);
  assert.equal(act(rules, p, { action: "claim_login" }, D0, {}).error, "Unknown order.");
  const before = act(rules, p, { action: "state" }, D0 + 10, { login }).state.castle;
  let out = act(rules, p, { action: "claim_login" }, D0 + 10, { login });
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.wood - before.resources.wood), 150);
  out = act(rules, out.state, { action: "claim_login" }, D0 + 20, { login });
  assert.equal(out.error, "You already have today's gift. Come back tomorrow.");
  out = act(rules, out.state, { action: "claim_login" }, D0 + DAY, { login });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.login.streak, 2);
});
