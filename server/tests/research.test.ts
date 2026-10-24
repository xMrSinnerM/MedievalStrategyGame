// The academy's research on the game server: the orders, and what studies
// change in attacks and raids. The rules themselves are checked against the
// game's in rules.test.ts.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { CastleState } from "../rules/castle_state.ts";
import { makeRules } from "../rules/load.ts";
import { act, fightRaid, newPlayer, type PvpRules, type Raid, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const T0 = 1_000_000;

/** A player with a keep at level 3, an academy and plenty in store. */
function scholar(name: string, academy = 1, spot = world.spots[1]) {
  const p = newPlayer(rules, world, name, T0, spot, pvp);
  p.castle.buildings.find((b) => b.type === "keep")!.level = 3;
  p.castle.buildings.push({ id: 50, type: "academy", level: academy, cell: [2, 14], target: 0, finish: 0 });
  p.castle.buildings.push({ id: 51, type: "storehouse", level: 6, cell: [6, 18], target: 0, finish: 0 });
  for (const r of rules.buildings.resources) p.castle.resources[r] = 9000;
  return p;
}

test("the academy needs a keep at level 3", () => {
  const p = newPlayer(rules, world, "Valentin", T0, world.spots[1], pvp);
  const out = act(rules, p, { action: "place", type: "academy", cell: [2, 14] }, T0);
  assert.equal(out.error, "Needs keep level 3");
});

test("research: started, refused, cancelled and finished", () => {
  let p = scholar("Valentin");
  assert.equal(act(rules, p, { action: "research", study: "magic" }, T0).error, "Unknown study");
  assert.equal(act(rules, p, { action: "research", study: "stonecutting" }, T0).error, "Needs academy level 2");
  assert.equal(act(rules, p, { action: "cancel_research" }, T0).error, "The academy isn't researching anything.");
  let out = act(rules, p, { action: "research", study: "forestry" }, T0);
  assert.equal(out.error, "");
  const cost = rules.buildings.studyCost("forestry", 1);
  assert.equal(out.state.castle.resources.stone, 9000 - cost.stone);
  assert.deepEqual(out.state.castle.studying, { study: "forestry", target: 1, finish: T0 + rules.buildings.studyTime("forestry", 1, 1) });
  p = out.state;
  assert.equal(act(rules, p, { action: "research", study: "masonry" }, T0 + 1).error, "The academy is already researching");
  const cancelled = act(rules, p, { action: "cancel_research" }, T0 + 1);
  assert.equal(cancelled.error, "");
  assert.equal(cancelled.state.castle.studying, null);
  assert.ok(cancelled.state.castle.resources.stone > 9000 - cost.stone);
  // Left to finish, it makes the woodcutters cut more.
  const before = CastleState.fromDict(rules.buildings, p.castle).productionPerHour().wood;
  out = act(rules, p, { action: "state" }, p.castle.studying!.finish + 1);
  assert.deepEqual(out.state.castle.research, { forestry: 1 });
  assert.equal(out.state.castle.studying, null);
  const after = CastleState.fromDict(rules.buildings, out.state.castle).productionPerHour().wood;
  assert.ok(Math.abs(after - before * 1.04) < 1e-9, "4% more wood");
  assert.equal(act(rules, out.state, { action: "research", study: "stonecutting" }, out.state.castle.last_update).error,
    "Needs academy level 2");
});

test("attack research rides with an army that has no commander, and Forced March shortens the road", () => {
  const plain = scholar("Plain");
  const read = scholar("Read");
  read.castle.research = { weaponsmiths: 3, forced_march: 5 };
  for (const p of [plain, read]) p.castle.troops = { spearman: 40 };
  const target = { name: "Victim", home: world.spots[2], protected: false };
  const send = (p: typeof plain) => act(rules, p, { action: "attack_player", target: "Victim", army: { spearman: 30 } }, T0, { pvp, target });
  const a = send(plain);
  const b = send(read);
  assert.equal(a.error, "");
  assert.equal(b.error, "");
  assert.equal(a.raid?.lead, undefined, "nothing researched, no commander: no lead");
  assert.deepEqual(b.raid?.lead, { id: 0, name: "", fx: { wall_attack: 0.06, yard_attack: 0.06 } });
  const travel = (r: typeof a.raid) => r!.arrive - r!.depart;
  assert.ok(Math.abs(travel(b.raid) - travel(a.raid) * 0.8) < 1e-6, "20% faster");
  // The report of a raid led by research alone names no commander.
  const victim = newPlayer(rules, world, "Victim", T0, world.spots[2], pvp);
  victim.castle.troops = { spearman: 1 };
  const fought = fightRaid(rules, pvp, victim, { ...b.raid!, id: 3 } as Raid);
  assert.equal(fought.attackerReport.lead, undefined);
  assert.equal(fought.lead, undefined);
});

test("hidden cellars keep resources from raiders, and the infirmary brings defenders back", () => {
  const raid: Raid = { id: 7, attacker_name: "Raider", defender_name: "Victim", army: { spearman: 400, archer: 200 },
    from: world.spots[1], to: world.spots[2], depart: T0, arrive: T0 + 600, back: T0 + 1200, state: "out", survivors: {}, loot: {} };
  const plain = scholar("Victim", 1, world.spots[2]);
  plain.castle.troops = { spearman: 60 };
  const read = structuredClone(plain);
  read.castle.research = { cellars: 5, infirmary: 5 };
  const a = fightRaid(rules, pvp, plain, raid);
  const b = fightRaid(rules, pvp, read, raid);
  assert.equal(a.attackerReport.winner, "a");
  assert.equal(b.attackerReport.winner, "a");
  const sum = (d: Record<string, number>) => Object.values(d).reduce((x, y) => x + y, 0);
  assert.ok(sum(b.loot) < sum(a.loot), "less is carried off");
  assert.equal(a.defenderReport.healed, undefined);
  assert.ok((b.defenderReport.healed?.spearman ?? 0) > 0, "some of the fallen come back");
  assert.equal(b.defender.castle.troops.spearman, (a.defender.castle.troops.spearman ?? 0) + b.defenderReport.healed!.spearman);
});

test("defence research joins the castellan's gear", () => {
  const p = scholar("Valentin");
  p.castle.research = { masonry: 2, militia: 1 };
  p.castle.armoury.castellan = { banner: { id: 1, slot: "banner", side: "defence", rarity: "common", name: "Banner", stats: { wall_bonus: 10 } } };
  const castle = CastleState.fromDict(rules.buildings, p.castle);
  assert.deepEqual(rules.gear.castellanEffects(castle), { wall_bonus: 0.16, wall_defence: 0.02, yard_defence: 0.02 });
});
