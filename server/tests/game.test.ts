// The game server's request handling (supabase/functions/game/game.ts),
// without the database.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { CastleState } from "../rules/castle_state.ts";
import { act, campsBeaten, castleLevel, castleView, checkName, fightRaid, isProtected, might, newPlayer, pickSpot, spyReport, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const T0 = 1_000_000;

test("names", () => {
  assert.equal(checkName("Valentin"), "");
  assert.equal(checkName("Sir Ælfric the 2nd"), "");
  assert.equal(checkName("ab"), "Names are 3 to 20 characters long.");
  assert.equal(checkName("x".repeat(21)), "Names are 3 to 20 characters long.");
  assert.equal(checkName("<script>"), "Use letters, numbers, spaces, ' _ and - only.");
  assert.equal(checkName(42), "Choose a name.");
});

test("a new player gets the starting castle and every camp", () => {
  const p = newPlayer(rules, world, " Valentin ", T0);
  assert.equal(p.name, "Valentin");
  assert.equal(p.castle.name, "Valentin's Castle");
  assert.equal(p.castle.last_update, T0);
  assert.equal(p.camps.length, (world.camps.length + (world.fortresses?.length ?? 0)));
  assert.deepEqual([p.home_x, p.home_y], world.home);
  assert.ok(p.camps.every((c) => c.defeats === 0 && c.rebuilt_at === 0));
});

test("time runs on the server's clock", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  const out = act(rules, p, { action: "state" }, T0 + 3600);
  assert.equal(out.error, "");
  assert.ok(out.state.castle.resources.wood > p.castle.resources.wood + 39, "an hour of wood");
  assert.equal(out.state.castle.last_update, T0 + 3600);
  assert.equal(p.castle.last_update, T0, "the stored state isn't changed in place");
});

test("orders are carried out or refused with a reason", () => {
  let p = newPlayer(rules, world, "Valentin", T0);
  let out = act(rules, p, { action: "place", type: "quarry", cell: [1, 1] }, T0);
  assert.equal(out.error, "");
  assert.equal(typeof out.result, "number");
  p = out.state;
  for (let k = 1; k < rules.buildings.builders(1); k++) {
    out = act(rules, p, { action: "place", type: "farm", cell: [18, 3 * k] }, T0);
    assert.equal(out.error, "", "every other builder put to work");
    p = out.state;
  }
  out = act(rules, p, { action: "place", type: "house", cell: [5, 5] }, T0 + 1);
  assert.equal(out.error, "All builders are busy");
  out = act(rules, p, { action: "place", type: "quarry", cell: "1,1" }, T0);
  assert.equal(out.error, "Bad cell.");
  out = act(rules, p, { action: "place", type: "constructor", cell: [1, 1] }, T0);
  assert.equal(out.error, "Unknown building");
  out = act(rules, p, { action: "recruit", unit: "spearman", amount: 5 }, T0);
  assert.equal(out.error, "Build a barracks first");
  out = act(rules, p, { action: "recruit", unit: "__proto__", amount: 5 }, T0);
  assert.equal(out.error, "Unknown unit");
  out = act(rules, p, { action: "fly" }, T0);
  assert.equal(out.error, "Unknown order.");
  out = act(rules, p, { action: "cancel", id: out.state.castle.buildings.at(-1)!.id }, T0 + 2);
  assert.equal(out.error, "");
});

test("an attack goes out, comes back and is reported once", () => {
  const p = newPlayer(rules, world, "Valentin", T0);
  p.castle.troops = { spearman: 300, archer: 100 };
  const near = p.camps.reduce((a, b) =>
    Math.hypot(a.position[0] - p.home_x, a.position[1] - p.home_y) < Math.hypot(b.position[0] - p.home_x, b.position[1] - p.home_y) ? a : b);
  let out = act(rules, p, { action: "attack", camp: near.id, army: { spearman: 300, archer: 100 } }, T0);
  assert.equal(out.error, "");
  assert.equal(out.state.marches.length, 1);
  out = act(rules, out.state, { action: "attack", camp: near.id, army: { constructor: 1 } }, T0);
  assert.equal(out.error, "Unknown unit.");
  out = act(rules, out.state, { action: "attack", camp: near.id, army: [1, 2] }, T0);
  assert.equal(out.error, "Bad army.");
  const back = out.state.marches[0].back;
  out = act(rules, out.state, { action: "state" }, back + 1);
  assert.equal(out.reports.length, 1);
  assert.equal(out.reports[0].winner, "a");
  assert.equal(out.state.marches.length, 0);
  out = act(rules, out.state, { action: "state" }, back + 2);
  assert.equal(out.reports.length, 0, "no second report");
});

test("new players get free spots, and camp levels count from their spot", () => {
  assert.deepEqual(world.spots[0], world.home);
  assert.ok(world.spots.length > 100);
  // At the game's own castle spot the camps start at the levels the game gives them.
  const first = newPlayer(rules, world, "First", T0);
  assert.deepEqual(first.camps.filter((c) => !c.fortress).map((c) => c.level), world.camps.map((c) => c.level));
  assert.ok(first.camps.filter((c) => c.fortress).every((c) => c.level === 1), "fortresses start at level 1");
  const taken: [number, number][] = [];
  const roomy = (s: [number, number]) => (world.invasion_spots?.[world.spots.indexOf(s)]?.length ?? 0) >= 3;
  const roomyCount = world.spots.filter(roomy).length;
  for (let i = 0; i < world.spots.length; i++) {
    const spot = pickSpot(world, taken);
    assert.ok(spot !== null);
    assert.ok(!taken.some(([x, y]) => x === spot[0] && y === spot[1]));
    // Spots with room for a Baron Invasion's camps go first.
    assert.equal(roomy(spot), i < roomyCount);
    taken.push(spot);
  }
  assert.equal(pickSpot(world, taken), null);
  const far = world.spots.reduce((a, b) => (Math.hypot(b[0] - world.home[0], b[1] - world.home[1]) >
    Math.hypot(a[0] - world.home[0], a[1] - world.home[1]) ? b : a));
  const p = newPlayer(rules, world, "Faraway", T0, far);
  assert.deepEqual([p.home_x, p.home_y], far);
  const nearest = p.camps.filter((c) => !c.fortress).reduce((a, b) => (Math.hypot(b.position[0] - far[0], b.position[1] - far[1]) <
    Math.hypot(a.position[0] - far[0], a.position[1] - far[1]) ? b : a));
  assert.equal(nearest.level, 1);
  assert.equal(castleLevel(p.castle), 1);
});

const pvp: PvpRules = json("data/pvp.json");

test("beginner protection lasts its hours, or until the keep grows", () => {
  const p = newPlayer(rules, world, "Newbie", T0, world.spots[3], pvp);
  assert.equal(p.protected_until, T0 + pvp.protection_hours * 3600);
  assert.ok(isProtected(p, pvp, T0 + 10));
  assert.ok(!isProtected(p, pvp, p.protected_until + 1));
  p.castle.buildings.find((b) => b.type === "keep")!.level = pvp.protection_until_keep;
  assert.ok(!isProtected(p, pvp, T0 + 10));
});

test("attacking a player: refusals, then the army marches and protection ends", () => {
  const me = newPlayer(rules, world, "Raider", T0, world.spots[1], pvp);
  me.castle.troops = { spearman: 40, archer: 10 };
  const target = { name: "Victim", home: world.spots[2], protected: false };
  const send = (army: unknown, t = target) => act(rules, me, { action: "attack_player", target: "x", army }, T0 + 5, { pvp, target: t });
  assert.equal(act(rules, me, { action: "attack_player", army: { spearman: 1 } }, T0, { pvp }).error, "There's no player by that name.");
  assert.equal(send({ spearman: 1 }, { ...target, name: "Raider" }).error, "That's your own castle.");
  assert.equal(send({ spearman: 1 }, { ...target, protected: true }).error, "That castle is under beginner protection.");
  me.castle.buildings.find((b) => b.type === "keep")!.level = 2 + pvp.attack_keep_gap!;
  assert.equal(send({ spearman: 1 }, { ...target, level: 1 }).error, "That castle is too small for you to attack.");
  assert.equal(send({ spearman: 41 }, { ...target, level: 2 }).error, "Your garrison doesn't have that many soldiers.");
  me.castle.buildings.find((b) => b.type === "keep")!.level = 1;
  assert.equal(send({ spearman: 41 }).error, "Your garrison doesn't have that many soldiers.");
  assert.equal(send({ spearman: 0 }).error, "Choose some soldiers to send.");
  const out = send({ spearman: 30, archer: 10 });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.troops.spearman, 10);
  assert.equal(out.state.castle.troops.archer, 0);
  assert.equal(out.state.protected_until, 0);
  const travel = rules.barons.marchTime(Math.hypot(world.spots[2][0] - world.spots[1][0], world.spots[2][1] - world.spots[1][1]));
  assert.deepEqual(out.raid?.army, { spearman: 30, archer: 10 });
  assert.equal(out.raid?.arrive, T0 + 5 + travel);
  assert.equal(out.raid?.back, T0 + 5 + 2 * travel);
});

test("a raid fights the garrison behind the wall and carries off loot", () => {
  const victim = newPlayer(rules, world, "Victim", T0, world.spots[2], pvp);
  const raid: Raid = { id: 7, attacker_name: "Raider", defender_name: "Victim", army: { spearman: 200, archer: 100 },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  victim.castle.troops = { spearman: 5 };
  const won = fightRaid(rules, pvp, victim, raid);
  assert.equal(won.attackerReport.winner, "a");
  assert.equal(won.defenderReport.role, "defender");
  assert.equal(won.defenderReport.name, "Raider");
  assert.equal(won.defender.castle.troops.spearman, 5 - won.attackerReport.b.spearman.lost);
  const before = CastleStateAt(victim, T0 + 600);
  for (const r of Object.keys(won.loot)) {
    assert.ok(won.loot[r] <= Math.floor(before[r] * pvp.loot_share));
    assert.ok(Math.abs(won.defender.castle.resources[r] - (before[r] - won.loot[r])) < 1e-6);
  }
  assert.ok(Object.values(won.loot).reduce((a, b) => a + b, 0) > 0);
  // A big garrison sends a small army home with nothing.
  victim.castle.troops = { spearman: 500, archer: 200 };
  const lost = fightRaid(rules, pvp, victim, { ...raid, army: { spearman: 10 } });
  assert.equal(lost.attackerReport.winner, "b");
  assert.deepEqual(lost.loot, {});
  // The attacker gets the survivors and the loot when they come home.
  const me = newPlayer(rules, world, "Raider", T0, world.spots[1], pvp);
  const home = act(rules, me, { action: "state" }, T0 + 1300, { homecomings: [{ ...raid, state: "home", survivors: won.survivors, loot: won.loot }] });
  assert.equal(home.state.castle.troops.spearman ?? 0, won.survivors.spearman ?? 0);
});

test("a spy costs gold and sees the soldiers at home and the wall", () => {
  const me = newPlayer(rules, world, "Watcher", T0, world.spots[1], pvp);
  const victim = newPlayer(rules, world, "Victim", T0, world.spots[2], pvp);
  victim.castle.troops = { archer: 12 };
  const target = { name: "Victim", home: world.spots[2], protected: true };
  const out = act(rules, me, { action: "spy", target: "Victim" }, T0, { pvp, target });
  assert.equal(out.error, "");
  assert.equal(out.state.castle.resources.gold, me.castle.resources.gold - pvp.spy_cost.gold);
  const seen = spyReport(rules, pvp, victim, T0 + 10);
  assert.deepEqual(seen.troops, { archer: 12 });
  assert.ok(seen.wall > 1);
  assert.equal(seen.protected, true);
  me.castle.resources.gold = 0;
  assert.equal(act(rules, me, { action: "spy" }, T0, { pvp, target }).error, "Not enough gold to send a spy.");
});

test("looking around another player's castle shows its buildings, not its soldiers or stores", () => {
  const p = newPlayer(rules, world, "Host", T0, world.home, pvp);
  p.castle.troops = { archer: 12 };
  const seen = castleView(rules, p, T0 + 10)!;
  assert.equal(seen.name, "Host");
  assert.equal(seen.castle_name, "Host's Castle");
  assert.equal(seen.level, castleLevel(p.castle));
  assert.deepEqual(seen.buildings.map((b) => b.type).sort(), p.castle.buildings.map((b) => b.type).sort());
  assert.ok(!("troops" in seen) && !("resources" in seen));
  assert.equal(castleView(rules, p, T0 + 10, true), null, "no outpost yet");
});

function CastleStateAt(p: ReturnType<typeof newPlayer>, t: number): Record<string, number> {
  const castle = CastleState.fromDict(rules.buildings, p.castle);
  castle.advanceTo(t);
  return castle.resources;
}

test("the leaderboard counts might and camps beaten", () => {
  const p = newPlayer(rules, world, "Ranked", T0, world.home, pvp);
  assert.equal(p.barons_beaten, 0);
  // Start: keep 1, wall 1, woodcutter 1, farm 1 and no soldiers.
  assert.equal(might(p.castle, pvp), 4 * pvp.might_per_building_level);
  p.castle.troops = { spearman: 300, archer: 100 };
  assert.equal(might(p.castle, pvp), 4 * pvp.might_per_building_level + 400 * pvp.might_per_soldier);
  const near = p.camps.reduce((a, b) =>
    Math.hypot(a.position[0] - p.home_x, a.position[1] - p.home_y) < Math.hypot(b.position[0] - p.home_x, b.position[1] - p.home_y) ? a : b);
  let out = act(rules, p, { action: "attack", camp: near.id, army: { spearman: 300, archer: 100 } }, T0, { pvp });
  out = act(rules, out.state, { action: "state" }, out.state.marches[0].back + 1, { pvp });
  assert.equal(out.reports[0].winner, "a");
  assert.equal(out.state.barons_beaten, 1);
  assert.equal(campsBeaten([{ ...out.reports[0], empty: true }]), 0);
});
