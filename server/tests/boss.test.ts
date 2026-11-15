// The Warlord's Stronghold (supabase/functions/game/boss.ts): the alliance
// boss raid. It rises for alliance members, never rises a level, and every
// defender slain there wears down the host the alliance shares.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { activeEvents, eventsView, lastBoss, type BossRules, type EventRules } from "../rules/events.ts";
import { act, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";
import { bossRises, hostAfter, hostSize, partyOf, takesPart } from "../../supabase/functions/game/boss.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  {}, {}, {}, json("data/fortresses.json"), json("data/horde.json"), {}, json("data/stronghold.json"));
const world: World = json("server/world/world.json");
const events: EventRules = json("data/events.json");
const boss: BossRules = events.weekly.find((e) => e.boss)!.boss!;
const utc = (s: string) => Date.parse(s) / 1000;
// 2026-10-30 is a Friday: the stronghold stands from 12:00 until Monday 00:00 UTC.
const START = utc("2026-10-30T12:00:00Z");
const END = START + 60 * 3600;
const member = { alliance_id: 7, joined: START - 86400 };
const ctx = (falls = 0, m = member) => ({ events: { rules: events, world }, boss: { member: m, falls } });

function player(t: number, troops: Record<string, number> = {}): PlayerState {
  const p = newPlayer(rules, world, "Valentin", t);
  p.castle.troops = troops;
  return p;
}

const stronghold = (p: PlayerState) => p.camps.find((c) => c.boss !== undefined);

test("the stronghold stands from Friday noon until Monday, after the invasion has ended", () => {
  assert.equal(activeEvents(events, START - 1).some((e) => e.boss), false);
  assert.equal(activeEvents(events, START - 1).some((e) => e.invasion), true);
  assert.equal(activeEvents(events, START + 60).some((e) => e.boss), true);
  assert.equal(activeEvents(events, START + 60).some((e) => e.invasion || e.horde), false, "the camp spots are free");
  assert.equal(activeEvents(events, END - 1).some((e) => e.boss), true);
  assert.equal(activeEvents(events, END).some((e) => e.boss), false);
  assert.equal(utc("2026-11-02T00:00:00Z"), END);
  assert.equal(lastBoss(events, END + 86400)!.start, START);
  assert.equal(eventsView(events, END + 60).recent.some((e) => e.boss), true, "the game still hears of it once it's over");
});

test("it rises only for members who were in their alliance when it began", () => {
  assert.equal(takesPart(undefined, START), false);
  assert.equal(takesPart({ alliance_id: null, joined: 0 }, START), false);
  assert.equal(takesPart({ alliance_id: 7, joined: START + 1 }, START), false, "joined too late for this one");
  assert.equal(takesPart(member, START), true);
  const p = { ...player(START - 3600), boss_key: 5, boss_damage: 400, boss: { claimed: 2, falls: 1 } };
  assert.equal(bossRises(p, events, world, START - 1, 0, member), p, "nothing before the event");
  assert.equal(bossRises(p, events, world, START + 60), p, "nothing outside an alliance");
  assert.equal(bossRises(p, events, world, START + 60, 0, { alliance_id: 7, joined: START + 30 }), p);
  const q = bossRises(p, events, world, START + 60, 0, member);
  const camp = stronghold(q)!;
  assert.equal(camp.id, `boss_${START}`);
  assert.equal(camp.name, boss.name);
  assert.equal(camp.level, boss.level, "keep level 1");
  assert.deepEqual(camp.position, world.invasion_spots![0].at(-1));
  assert.deepEqual([camp.boss, camp.until, camp.rebuild], [START, END, boss.rally]);
  assert.deepEqual([q.boss_key, q.boss_damage, q.boss], [START, 0, { claimed: 0, falls: 0 }], "the count starts again");
  assert.equal(bossRises(q, events, world, START + 120, 0, member), q, "asking again changes nothing");
  const big = player(START - 3600);
  big.castle.buildings.find((b) => b.type === "keep")!.level = 4;
  assert.equal(stronghold(bossRises(big, events, world, START, 0, member))!.level, boss.level + 3 * boss.level_per_keep);
});

test("every defender slain counts, win or lose, and the stronghold never rises a level", () => {
  let out = act(rules, player(START - 3600, { swordsman: 400, spearman: 3 }), { action: "state" }, START + 10, ctx());
  const camp = stronghold(out.state)!;
  const garrison = Object.values(rules.barons.forCamp(camp).garrison(camp.level)).reduce((a, b) => a + b, 0);
  // A hopeless attack still slays a few.
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { spearman: 3 } }, START + 20, ctx());
  assert.equal(out.error, "");
  let march = out.state.marches[0];
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx());
  assert.equal(out.reports[0].winner, "b");
  assert.equal(out.reports[0].boss, START);
  const first = out.reports[0].slain!;
  assert.ok(first >= 0 && first < garrison);
  assert.equal(out.state.boss_damage, first);
  // A win slays the whole garrison, which then rallies; the level stays.
  out = act(rules, out.state, { action: "attack", camp: camp.id, army: { swordsman: 400 } }, march.arrive + 2, ctx());
  march = out.state.marches.find((m) => m.state === "out")!;
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx());
  const report = out.reports[0];
  assert.equal(report.winner, "a");
  assert.equal(report.slain, garrison);
  assert.equal(report.leveled, false);
  assert.equal(out.state.boss_damage, first + garrison);
  assert.equal(out.state.horde_points, 0);
  assert.equal(out.state.event_points, 0);
  const after = stronghold(out.state)!;
  assert.deepEqual([after.level, after.defeats, after.rebuilt_at], [camp.level, 0, march.arrive + boss.rally]);
  // It leaves once the event is over; the count is kept until the next one.
  out = act(rules, out.state, { action: "state" }, END + 1, ctx());
  out = act(rules, out.state, { action: "state" }, END + 2, ctx());
  assert.equal(stronghold(out.state), undefined);
  assert.equal(out.state.boss_damage, first + garrison);
});

test("a battle fought after the stronghold is abandoned counts for nothing", () => {
  let out = act(rules, player(END - 60, { swordsman: 400 }), { action: "state" }, END - 10, ctx());
  out = act(rules, out.state, { action: "attack", camp: stronghold(out.state)!.id, army: { swordsman: 400 } }, END - 5, ctx());
  const march = out.state.marches[0];
  assert.ok(march.arrive > END);
  out = act(rules, out.state, { action: "state" }, march.arrive + 1, ctx());
  assert.equal(out.reports[0].slain, 0);
  assert.equal(out.state.boss_damage, 0);
});

test("the host grows with the alliance and with every fall, and falls once for each chest", () => {
  assert.equal(hostSize(boss, 1, 0), boss.host_base + boss.host_per_member);
  assert.equal(hostSize(boss, 10, 0), boss.host_base + 10 * boss.host_per_member);
  assert.equal(hostSize(boss, 10, 1), Math.round(hostSize(boss, 10, 0) * boss.host_growth));
  const one = hostSize(boss, 2, 0);
  assert.deepEqual(hostAfter(boss, one - 1, 2), { slain: one - 1, members: 2, falls: 0, max_falls: boss.falls.length, size: one, down: one - 1 });
  assert.deepEqual(hostAfter(boss, one + 5, 2), { slain: one + 5, members: 2, falls: 1, max_falls: boss.falls.length, size: hostSize(boss, 2, 1), down: 5 });
  const done = hostAfter(boss, 10_000_000, 2);
  assert.deepEqual([done.falls, done.size, done.down], [boss.falls.length, 0, 0]);
});

test("only members who were there when it rose count, in the host and in the slaying", () => {
  const rows = [
    { name: "Bera", boss_key: START, boss_damage: 300, alliance_joined: START - 10 },
    { name: "Aldo", boss_key: START, boss_damage: 300, alliance_joined: START - 10 },
    { name: "Cyn", boss_key: START - 7 * 86400, boss_damage: 900, alliance_joined: START - 10 },
    { name: "Dov", boss_key: START, boss_damage: 5000, alliance_joined: START + 10 },
    { name: "Eda", boss_key: 0, boss_damage: 0, alliance_joined: START - 10 },
  ];
  const party = partyOf(boss, rows, START);
  assert.deepEqual(party.players, [{ name: "Aldo", points: 300 }, { name: "Bera", points: 300 }]);
  assert.equal(party.host.slain, 600);
  assert.equal(party.host.members, 4, "the latecomer isn't counted");
});

test("your own rewards go by the defenders you slew, in order, until the next stronghold", () => {
  const p = { ...bossRises(player(START - 3600), events, world, START, 0, member), boss_damage: boss.rewards[1].points };
  let out = act(rules, p, { action: "claim_boss_reward", tier: 1 }, START + 60, ctx());
  assert.equal(out.error, "Claim the rewards in order.");
  const wood = p.castle.resources.wood;
  out = act(rules, p, { action: "claim_boss_reward", tier: 0 }, START + 60, ctx());
  assert.equal(out.error, "");
  assert.equal(out.state.boss!.claimed, 1);
  assert.ok(out.state.castle.resources.wood > wood);
  out = act(rules, out.state, { action: "claim_boss_reward", tier: 0 }, START + 61, ctx());
  assert.equal(out.error, "You already have that reward.");
  out = act(rules, out.state, { action: "claim_boss_reward", tier: 1 }, END + 3600, ctx());
  assert.equal(out.error, "", "still open after the event");
  out = act(rules, out.state, { action: "claim_boss_reward", tier: 2 }, END + 3600, ctx());
  assert.equal(out.error, `That reward needs ${boss.rewards[2].points} defenders slain.`);
  // Next week's stronghold starts everyone again.
  out = act(rules, out.state, { action: "claim_boss_reward", tier: 2 }, START + 7 * 86400 + 60, ctx());
  assert.deepEqual([out.state.boss_damage, out.state.boss], [0, { claimed: 0, falls: 0 }]);
  assert.notEqual(out.error, "");
});

test("a fall's chest goes to members who did their part, once per fall", () => {
  const base = bossRises(player(START - 3600), events, world, START, 0, member);
  let out = act(rules, { ...base, boss_damage: boss.min_damage }, { action: "claim_boss_chest" }, START + 60, ctx(0));
  assert.equal(out.error, "Your alliance hasn't brought the stronghold down again yet.");
  out = act(rules, { ...base, boss_damage: boss.min_damage - 1 }, { action: "claim_boss_chest" }, START + 60, ctx(1));
  assert.equal(out.error, `Slay ${boss.min_damage} defenders yourself to share in the chests.`);
  const marks = (base.castle as { armoury?: { marks?: number } }).armoury?.marks ?? 0;
  out = act(rules, { ...base, boss_damage: boss.min_damage }, { action: "claim_boss_chest" }, START + 60, ctx(2));
  assert.equal(out.error, "");
  assert.equal(out.state.boss!.falls, 1);
  assert.equal((out.state.castle as { armoury: { marks: number } }).armoury.marks - marks, boss.falls[0].marks);
  out = act(rules, out.state, { action: "claim_boss_chest" }, START + 61, ctx(2));
  assert.equal(out.error, "");
  assert.equal(out.state.boss!.falls, 2);
  out = act(rules, out.state, { action: "claim_boss_chest" }, START + 62, ctx(2));
  assert.equal(out.error, "Your alliance hasn't brought the stronghold down again yet.");
  out = act(rules, { ...out.state, boss: { claimed: 0, falls: boss.falls.length } }, { action: "claim_boss_chest" }, START + 63, ctx(9));
  assert.equal(out.error, "You have every chest.");
  out = act(rules, player(START - 3600), { action: "claim_boss_chest" }, START + 60, { events: { rules: events, world } });
  assert.notEqual(out.error, "", "nothing outside an alliance");
});
