// Seasons (server/rules/seasons.ts) and the claim_season, claim_season_prize orders.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import {
  allianceStandings, claimPrize, claimTrack, placeIn, prizeFor, renown, rollSeason, seasonColumns, seasonEnd, seasonKey, seasonStart,
  type SeasonRules,
} from "../rules/seasons.ts";
import { setTitle, type AchievementRules } from "../rules/achievements.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const seasons: SeasonRules = json("data/seasons.json");
const achievements: AchievementRules = json("data/achievements.json");
const world: World = json("server/world/world.json");
const OCT = Date.UTC(2026, 9, 15) / 1000;
const NOV = Date.UTC(2026, 10, 2) / 1000;

test("a season is a calendar month", () => {
  assert.equal(seasonKey(OCT), 2026 * 12 + 9);
  assert.equal(seasonStart(seasonKey(OCT)), Date.UTC(2026, 9, 1) / 1000);
  assert.equal(seasonEnd(seasonKey(OCT)), Date.UTC(2026, 10, 1) / 1000);
  assert.equal(seasonEnd(2026 * 12 + 11), Date.UTC(2027, 0, 1) / 1000, "December ends at New Year");
  assert.equal(seasonKey(seasonEnd(seasonKey(OCT)) - 1), seasonKey(OCT));
});

test("the track rises, its rewards are real, and the prizes are ranked", () => {
  for (let i = 1; i < seasons.track.length; i++) assert.ok(seasons.track[i].renown > seasons.track[i - 1].renown);
  for (const t of seasons.track) {
    for (const r of Object.keys(t.reward.resources ?? {})) assert.ok(rules.buildings.resources.includes(r));
    for (const u of Object.keys(t.reward.troops ?? {})) assert.ok(rules.buildings.hasUnit(u));
  }
  assert.equal(prizeFor(seasons.players, 1)?.id, "champion");
  assert.equal(prizeFor(seasons.players, 2)?.id, "hero");
  assert.equal(prizeFor(seasons.players, 25)?.id, "contender");
  assert.equal(prizeFor(seasons.players, 26), undefined);
  assert.equal(prizeFor(seasons.players, 0), undefined);
});

test("renown counts this month's work, the track pays out, and a new month starts over", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", OCT);
  assert.ok(rollSeason(castle, seasons, OCT));
  assert.equal(renown(castle, seasons), 0);
  castle.stats.barons += 8;
  castle.stats.trained += 100;
  castle.buildings.find((b) => b.type === "farm")!.level += 3;
  assert.equal(renown(castle, seasons), 8 * 25 + 100 * 0.5 + 3 * 10);
  assert.equal(claimTrack(castle, seasons, OCT), "");
  assert.equal(claimTrack(castle, seasons, OCT), "You need 750 renown for that.");
  castle.stats.barons += 1000;
  for (let i = 1; i < seasons.track.length; i++) assert.equal(claimTrack(castle, seasons, OCT), "", `tier ${i}`);
  assert.equal(claimTrack(castle, seasons, OCT), "Every reward this season is claimed.");
  assert.deepEqual(castle.season.honours, [`season:${seasonKey(OCT)}:renowned`]);
  const earned = renown(castle, seasons);
  assert.ok(rollSeason(castle, seasons, NOV));
  assert.deepEqual(castle.season.last, { key: seasonKey(OCT), points: earned, claimed: false });
  assert.equal(renown(castle, seasons), 0);
  assert.equal(castle.season.track, 0);
  assert.deepEqual(seasonColumns(castle, seasons), { season_key: seasonKey(NOV), season_points: 0, last_season_key: seasonKey(OCT), last_season_points: earned });
  // Season titles can be shown once won.
  assert.equal(setTitle(castle, achievements, `season:${seasonKey(OCT)}:renowned`), "");
  assert.equal(setTitle(castle, achievements, `season:${seasonKey(OCT)}:champion`), "You haven't earned that title yet.");
});

test("last season's prizes go by place, once", () => {
  const castle = CastleState.createNew(rules.buildings, "c", "C", "player", OCT);
  rollSeason(castle, seasons, OCT);
  castle.stats.barons += 10;
  rollSeason(castle, seasons, NOV);
  const gold = castle.resources.gold;
  assert.equal(claimPrize(castle, seasons, 2, 1, NOV), "");
  assert.equal(castle.resources.gold - gold, 5000 + 3000);
  assert.deepEqual(castle.season.honours, [`season:${seasonKey(OCT)}:hero`, `season:${seasonKey(OCT)}:first_banner`]);
  assert.equal(claimPrize(castle, seasons, 2, 1, NOV), "You already have last season's prize.");
  const idle = CastleState.createNew(rules.buildings, "d", "D", "player", OCT);
  rollSeason(idle, seasons, OCT);
  rollSeason(idle, seasons, NOV);
  assert.equal(claimPrize(idle, seasons, 1, 1, NOV), "You earned no renown last season.");
});

test("places among players and alliances", () => {
  const K = 100;
  const rows = [
    { alliance_id: 1, season_key: K, season_points: 500, last_season_key: -1, last_season_points: 0 },
    { alliance_id: 1, season_key: K + 1, season_points: 0, last_season_key: K, last_season_points: 900 },
    { alliance_id: 2, season_key: K, season_points: 1200, last_season_key: -1, last_season_points: 0 },
    { alliance_id: null, season_key: K, season_points: 700, last_season_key: -1, last_season_points: 0 },
  ];
  assert.equal(placeIn(rows, K, 1200), 1);
  assert.equal(placeIn(rows, K, 900), 2, "a player who moved on to the next season still counts");
  assert.equal(placeIn(rows, K, 500), 4);
  assert.equal(placeIn(rows, K, 0), 0);
  assert.deepEqual(allianceStandings(rows, K), [[1, 1400], [2, 1200]]);
});

test("the season orders", () => {
  const p = newPlayer(rules, world, "Valentin", OCT);
  assert.equal(act(rules, p, { action: "claim_season" }, OCT, {}).error, "Unknown order.");
  let out = act(rules, p, { action: "state" }, OCT, { seasons });
  assert.equal(out.state.castle.season.key, seasonKey(OCT));
  out.state.castle.stats.barons = 20;
  out = act(rules, out.state, { action: "claim_season" }, OCT + 10, { seasons });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.season.track, 1);
  out = act(rules, out.state, { action: "claim_season_prize" }, NOV, { seasons, seasonPlace: { player: 1, alliance: 0 } });
  assert.equal(out.error, "");
  assert.deepEqual(out.state.castle.season.honours, [`season:${seasonKey(OCT)}:champion`]);
});
