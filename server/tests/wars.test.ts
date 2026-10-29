// Alliance wars (supabase/functions/game/wars.ts): weekly seasons, war points
// for holding, taking and defending capitals, the standings and the prizes.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import type { VillageInfo } from "../rules/villages.ts";
import { newPlayer, type World } from "../../supabase/functions/game/game.ts";
import {
  captureEntry, checkClaim, defenceEntry, givePrize, holdDue, holdEntries, lastSeason, prizeFor, ranked, seasonAt, standings,
  warBoard, type WarAlliance, type WarRules,
} from "../../supabase/functions/game/wars.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  {}, {}, json("data/capitals.json"), json("data/fortresses.json"), json("data/horde.json"));
const world: World = json("server/world/world.json");
const war: WarRules = json("data/wars.json");
const utc = (s: string) => Date.parse(s) / 1000;
// 2026-10-26 is a Monday: a season runs from Monday 00:00 UTC to the next.
const MONDAY = utc("2026-10-26T00:00:00Z");
const WEEK = 7 * 86400;
const HOUR = 3600;
const highford = world.capitals!.find((c) => c.name === "Highford")!;
const wexmoor = world.capitals!.find((c) => c.name === "Wexmoor")!;
const lions: WarAlliance = { id: 1, name: "Lions", tag: "LION" };
const wolves: WarAlliance = { id: 2, name: "Wolves", tag: "WOLF" };

test("a season runs from Monday 00:00 UTC for a week, and the last one is the week before", () => {
  assert.deepEqual(seasonAt(war, MONDAY), { start: MONDAY, end: MONDAY + WEEK });
  assert.deepEqual(seasonAt(war, MONDAY - 1), { start: MONDAY - WEEK, end: MONDAY });
  assert.deepEqual(seasonAt(war, MONDAY + WEEK - 1), { start: MONDAY, end: MONDAY + WEEK });
  assert.deepEqual(lastSeason(war, MONDAY + 3 * 86400), { start: MONDAY - WEEK, end: MONDAY });
});

test("hold points count whole hours since the capital was last counted, per level of the capital", () => {
  const t = MONDAY + 5 * HOUR + 1200;
  assert.deepEqual(holdDue(MONDAY + HOUR, 0, t), { from: MONDAY + HOUR, to: MONDAY + 5 * HOUR });
  assert.deepEqual(holdDue(0, MONDAY + 2 * HOUR + 1800, t), { from: MONDAY + 2 * HOUR + 1800, to: MONDAY + 5 * HOUR },
    "from when it was taken");
  assert.equal(holdDue(MONDAY + 5 * HOUR, 0, t), null, "already counted this hour");
  assert.equal(highford.level, 2);
  const e = holdEntries(war, highford, lions, MONDAY + HOUR, MONDAY + 5 * HOUR);
  assert.equal(e.length, 1);
  assert.deepEqual([e[0].season, e[0].kind, e[0].points, e[0].capital, e[0].tag], [MONDAY, "hold", 80, highford.id, "LION"]);
  const half = holdEntries(war, wexmoor, lions, MONDAY, MONDAY + 1800);
  assert.equal(half[0].points, 5, "half an hour of a level 1 capital");
});

test("hold time over the turn of a season counts for each season", () => {
  const e = holdEntries(war, wexmoor, wolves, MONDAY - 2 * HOUR, MONDAY + 3 * HOUR);
  assert.deepEqual(e.map((x) => [x.season, x.points]), [[MONDAY - WEEK, 20], [MONDAY, 30]]);
});

test("taking a capital counts once a season, holding one counts the attackers who fell, up to a cap", () => {
  const take = captureEntry(war, highford, lions, MONDAY + 60, false)!;
  assert.deepEqual([take.kind, take.points, take.season], ["capture", 300, MONDAY]);
  assert.equal(captureEntry(war, highford, lions, MONDAY + 60, true), null, "taken before this season");
  const fell = { spearman: { start: 100, lost: 60 }, archer: { start: 50, lost: 20 } };
  assert.equal(defenceEntry(war, wexmoor, wolves, MONDAY, fell)!.points, 40);
  const many = { spearman: { start: 2000, lost: 2000 } };
  assert.equal(defenceEntry(war, wexmoor, wolves, MONDAY, many)!.points, 100, "at most defence_max per level");
  assert.equal(defenceEntry(war, highford, wolves, MONDAY, many)!.points, 200);
  assert.equal(defenceEntry(war, wexmoor, wolves, MONDAY, { spearman: { start: 1, lost: 1 } }), null, "nothing for half a point");
});

test("standings add up a season's points, most first, and the same points share a place", () => {
  const entries = [
    ...holdEntries(war, highford, lions, MONDAY, MONDAY + 10 * HOUR),
    captureEntry(war, highford, lions, MONDAY, false)!,
    captureEntry(war, wexmoor, wolves, MONDAY, false)!,
    defenceEntry(war, wexmoor, wolves, MONDAY + 60, { spearman: { start: 900, lost: 900 } })!,
    ...holdEntries(war, wexmoor, wolves, MONDAY - 5 * HOUR, MONDAY),
  ];
  const s = standings(entries, MONDAY);
  assert.deepEqual(s.map((x) => [x.name, x.points, x.captures, x.defences, x.rank]), [["Lions", 500, 1, 0, 1], ["Wolves", 250, 1, 1, 2]]);
  assert.deepEqual(standings(entries, MONDAY - WEEK).map((x) => [x.name, x.points]), [["Wolves", 50]]);
  const tie = ranked([
    { alliance_id: 1, name: "A", tag: "A", points: 50, captures: 0, defences: 0 },
    { alliance_id: 2, name: "B", tag: "B", points: 90, captures: 0, defences: 0 },
    { alliance_id: 3, name: "C", tag: "C", points: 50, captures: 0, defences: 0 },
  ]);
  assert.deepEqual(tie.map((x) => [x.name, x.rank]), [["B", 1], ["A", 2], ["C", 2]]);
});

test("prizes go by place; every member who was in the alliance before the season ended claims one, once", () => {
  assert.equal(prizeFor(war.prizes, 1), war.prizes[0]);
  assert.equal(prizeFor(war.prizes, 3), war.prizes[1]);
  assert.equal(prizeFor(war.prizes, 7), war.prizes[2]);
  assert.equal(prizeFor(war.prizes, 40), war.prizes[3]);
  assert.equal(prizeFor(war.prizes, 0), undefined);
  const t = MONDAY + 86400;
  const first = { alliance_id: 1, name: "Lions", tag: "LION", points: 900, captures: 2, defences: 1, rank: 1 };
  const me = { alliance_id: 1, joined: MONDAY - 3 * 86400, war_claimed: 0 };
  assert.equal(checkClaim(war, me, first, t), war.prizes[0]);
  assert.match(String(checkClaim(war, { ...me, war_claimed: MONDAY - WEEK }, first, t)), /already/);
  assert.match(String(checkClaim(war, { ...me, joined: MONDAY + 60 }, first, t)), /after the last season ended/);
  assert.match(String(checkClaim(war, { ...me, alliance_id: null }, undefined, t)), /Join an alliance/);
  assert.match(String(checkClaim(war, me, undefined, t)), /no war points/);
  assert.equal(checkClaim(war, { ...me, war_claimed: MONDAY - 2 * WEEK }, first, t), war.prizes[0], "a prize from two seasons ago is no bar");
});

test("a prize fills the storage and the garrison", () => {
  const p = newPlayer(rules, world, "Valentin", MONDAY);
  const castle = CastleState.fromDict(rules.buildings, p.castle);
  const cap = castle.storageCapacity();
  castle.resources.gold = cap - 100;
  const wood = castle.resources.wood;
  givePrize(castle, war.prizes[0]);
  assert.equal(castle.resources.gold, cap, "what doesn't fit is lost");
  assert.equal(castle.resources.wood, Math.min(cap, wood + 3000));
  assert.equal(castle.troops.horseman ?? 0, 60);
});

test("the war screen shows both seasons, who holds the capitals and the prize the player can claim", () => {
  const t = MONDAY + 2 * HOUR;
  const last = ranked([{ alliance_id: 2, name: "Wolves", tag: "WOLF", points: 1234.6, captures: 3, defences: 2 }]);
  const now = ranked([{ alliance_id: 1, name: "Lions", tag: "LION", points: 40.5, captures: 1, defences: 0 }]);
  const caps = world.capitals!.map((c: VillageInfo) => ({ id: c.id, name: c.name, level: c.level, owner: c.id === highford.id ? "Valentin" : "",
    alliance_id: c.id === highford.id ? 1 : null, tag: c.id === highford.id ? "LION" : "" }));
  const b = warBoard(war, t, now, last, caps, { alliance_id: 2, joined: 0, war_claimed: 0 });
  assert.deepEqual([b.season.start, b.season.end, b.last.start], [MONDAY, MONDAY + WEEK, MONDAY - WEEK]);
  assert.deepEqual(b.season.alliances.map((a) => [a.name, a.points, a.capitals]), [["Lions", 40, 1]]);
  assert.equal(b.last.alliances[0].points, 1234);
  assert.equal(b.capitals.find((c) => c.id === highford.id)!.per_hour, 20);
  assert.equal(b.capitals.find((c) => c.id === wexmoor.id)!.per_hour, 0);
  assert.deepEqual([b.mine!.now, b.mine!.last!.rank, b.prize.can_claim, b.prize.prize], [null, 1, true, war.prizes[0]]);
  const done = warBoard(war, t, now, last, caps, { alliance_id: 2, joined: 0, war_claimed: MONDAY - WEEK });
  assert.deepEqual([done.prize.can_claim, done.prize.claimed, done.prize.prize], [false, true, war.prizes[0]]);
  const alone = warBoard(war, t, now, last, caps, { alliance_id: null, joined: 0, war_claimed: 0 });
  assert.equal(alone.mine, null);
  assert.match(alone.prize.why, /Join an alliance/);
});
