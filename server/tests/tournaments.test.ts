// Weekly alliance tournaments (supabase/functions/game/tournaments.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import type { SeasonRules } from "../rules/seasons.ts";
import {
  bracket, checkClaim, claimableWeek, draw, placeOf, rollTourney, roundKey, roundPoints, roundScores, schedule, seedOrder, slots,
  tourneyColumns, weekAt, type Entrant, type TourneyRules, type TourneyRow,
} from "../../supabase/functions/game/tournaments.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const tourney: TourneyRules = json("data/tournaments.json");
const seasons: SeasonRules = json("data/seasons.json");
const HOUR = 3600;
// Monday 2026-11-02 00:00 UTC.
const WEEK = Date.UTC(2026, 10, 2) / 1000;

const alliance = (id: number, might: number, members = 3) => ({ id, name: `Alliance ${id}`, tag: `A${id}`, members, might });

test("weeks start on Monday at midnight UTC", () => {
  assert.equal(weekAt(tourney, WEEK), WEEK);
  assert.equal(weekAt(tourney, WEEK + 5 * 86400 + 7), WEEK);
  assert.equal(weekAt(tourney, WEEK - 1), WEEK - 7 * 86400);
  assert.equal(roundKey(tourney, WEEK + 10 * HOUR), WEEK);
  assert.equal(roundKey(tourney, WEEK + 50 * HOUR), WEEK + 48 * HOUR);
  assert.equal(roundKey(tourney, WEEK + 100 * HOUR), WEEK + 96 * HOUR);
  assert.equal(roundKey(tourney, WEEK + 150 * HOUR), 0, "Sunday is a rest day");
});

test("brackets fit the alliances, seeded so the best meet last", () => {
  assert.deepEqual(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
  assert.deepEqual(seedOrder(4), [1, 4, 2, 3]);
  assert.equal(slots(tourney, 1), 0);
  assert.equal(slots(tourney, 2), 2);
  assert.equal(slots(tourney, 3), 4);
  assert.equal(slots(tourney, 5), 8);
  assert.equal(slots(tourney, 20), 8);
  assert.deepEqual(schedule(tourney, WEEK, 2).map((r) => r.name), ["Final"]);
  assert.equal(schedule(tourney, WEEK, 2)[0].start, WEEK + 96 * HOUR, "the final is always the last round");
  assert.deepEqual(schedule(tourney, WEEK, 8).map((r) => r.name), ["Quarter-finals", "Semi-finals", "Final"]);
  const drawn = draw(tourney, [alliance(1, 50), alliance(2, 900), alliance(3, 300, 0), alliance(4, 400)]);
  assert.deepEqual(drawn.map((e) => [e.id, e.seed]), [[2, 1], [4, 2], [1, 3]], "empty alliances stay out");
  assert.deepEqual(draw(tourney, [alliance(1, 50)]), [], "one alliance is no tournament");
});

test("matches go to the alliance that earns more renown, ties to the higher seed", () => {
  const entrants: Entrant[] = draw(tourney, [1, 2, 3, 4, 5].map((id) => alliance(id, 1000 - id)));
  // Quarter-finals: 1 v bye, 4 v 5, 2 v bye, 3 v bye. Alliance 5 outscores 4; 3 ties 2 in the semi and goes out.
  const scores = new Map<number, Map<number, number>>([
    [WEEK, new Map([[4, 100], [5, 250]])],
    [WEEK + 48 * HOUR, new Map([[1, 80], [5, 120], [2, 60], [3, 60]])],
    [WEEK + 96 * HOUR, new Map([[5, 500], [2, 700]])],
  ]);
  const at = (t: number) => bracket(tourney, WEEK, entrants, t, (start) => scores.get(start) ?? new Map());
  const early = at(WEEK + HOUR);
  assert.deepEqual(early[0].matches.map((m) => m.winner), [1, null, 2, 3], "byes go through at once");
  assert.equal(early[0].matches[1].b_points, 250, "scores show while the round is on");
  assert.deepEqual(early[1].matches.map((m) => [m.a, m.b]), [[1, 0], [2, 3]], "the undecided match leaves a place open");
  assert.equal(placeOf(early, 1), 0, "nobody has a place before the final");
  const done = at(WEEK + 150 * HOUR);
  assert.deepEqual(done.map((r) => r.matches.map((m) => m.winner)), [[1, 5, 2, 3], [5, 2], [2]]);
  assert.deepEqual([2, 5, 1, 3, 4].map((id) => placeOf(done, id)), [1, 2, 4, 4, 8]);
  const member = { alliance_id: 5, joined: WEEK - 10, claimed: 0 };
  assert.deepEqual(checkClaim(tourney, member, WEEK, done), tourney.prizes[1]);
  assert.equal(checkClaim(tourney, { ...member, claimed: WEEK }, WEEK, done), "You already have your tournament prize.");
  assert.equal(checkClaim(tourney, { ...member, joined: WEEK + 5 }, WEEK, done), "You joined your alliance after the bracket was drawn.");
  assert.equal(checkClaim(tourney, { ...member, alliance_id: 9 }, WEEK, done), "Your alliance wasn't in the tournament.");
  assert.equal(checkClaim(tourney, member, WEEK, at(WEEK + 100 * HOUR)), "The tournament isn't over yet.");
  assert.equal(claimableWeek(tourney, WEEK + 100 * HOUR), WEEK - 7 * 86400);
  assert.equal(claimableWeek(tourney, WEEK + 150 * HOUR), WEEK);
});

test("castles count the renown they earn in each round", () => {
  const c = CastleState.createNew(rules.buildings, "c", "Castle", "player", WEEK - 100);
  rollTourney(c, tourney, seasons, WEEK + HOUR);
  assert.equal(c.tourney.key, WEEK);
  assert.equal(roundPoints(c, seasons), 0);
  (c.stats as unknown as Record<string, number>).barons = ((c.stats as unknown as Record<string, number>).barons ?? 0) + 2;
  assert.equal(roundPoints(c, seasons), 2 * seasons.renown.barons);
  assert.equal(rollTourney(c, tourney, seasons, WEEK + 2 * HOUR), false);
  rollTourney(c, tourney, seasons, WEEK + 49 * HOUR);
  assert.deepEqual(tourneyColumns(c, seasons), { tourney_key: WEEK + 48 * HOUR, tourney_points: 0, last_tourney_key: WEEK,
    last_tourney_points: 50 });
  const back = CastleState.fromDict(rules.buildings, structuredClone(c.toDict()));
  assert.deepEqual(back.tourney, c.tourney);
  const rows: TourneyRow[] = [
    { alliance_id: 1, alliance_joined: 0, tourney_key: WEEK + 48 * HOUR, tourney_points: 0, last_tourney_key: WEEK, last_tourney_points: 50 },
    { alliance_id: 1, alliance_joined: 0, tourney_key: WEEK, tourney_points: 30, last_tourney_key: 0, last_tourney_points: 0 },
    { alliance_id: 1, alliance_joined: WEEK + 5, tourney_key: WEEK, tourney_points: 999, last_tourney_key: 0, last_tourney_points: 0 },
    { alliance_id: 2, alliance_joined: 0, tourney_key: WEEK, tourney_points: 10, last_tourney_key: 0, last_tourney_points: 0 },
    { alliance_id: null, alliance_joined: 0, tourney_key: WEEK, tourney_points: 70, last_tourney_key: 0, last_tourney_points: 0 },
  ];
  assert.deepEqual([...roundScores(rows, WEEK).entries()], [[1, 80], [2, 10]], "late joiners and loners don't count");
});
