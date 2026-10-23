// Resource villages on the server: their numbers, what they send their
// owner, sending armies and guards, and the battles for them
// (server/rules/villages.ts, supabase/functions/game/villages.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { CastleState } from "../rules/castle_state.ts";
import { makeRules } from "../rules/load.ts";
import { untouched, type VillageInfo, type VillageState } from "../rules/villages.ts";
import { act, newPlayer, type PlayerState, type Raid, type World } from "../../supabase/functions/game/game.ts";
import { resolveVillageRaid, type VillageTarget } from "../../supabase/functions/game/villages.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const data = json("data/villages.json");
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), data);
const world: World = json("server/world/world.json");
const v = rules.villages;
const T0 = 1_000_000;
const HOUR = 3600;

function player(name: string, keep: number, troops: Record<string, number> = {}): PlayerState {
  const p = act(rules, newPlayer(rules, world, name, T0), { action: "state" }, T0).state;
  for (const b of p.castle.buildings) if (b.type === "keep") b.level = keep;
  p.castle.troops = { ...p.castle.troops, ...troops };
  return p;
}

function target(info: VillageInfo, state: VillageState, held = 0, ally = false): VillageTarget {
  return { info, state, held, ally };
}

const first = world.villages![0];

test("the world has villages of every level and resource, with the numbers from the data", () => {
  const vs = world.villages!;
  const oldVillages = json("data/settlements.json").settlements.filter((s: { type: string }) => s.type === "village");
  assert.equal(vs.length, data.placement.count + oldVillages.length, "the placed villages and the old ones");
  for (const s of oldVillages) {
    const found = vs.find((x) => x.id === s.id);
    assert.ok(found && found.name === s.name && found.resource in data.yields, `${s.name} is a resource village`);
  }
  assert.deepEqual([...new Set(vs.map((x) => x.level))].sort(), [1, 2, 3, 4, 5]);
  assert.deepEqual([...new Set(vs.map((x) => x.resource))].sort(), ["food", "gold", "stone", "wood"]);
  assert.equal(new Set(vs.map((x) => x.id)).size, vs.length, "ids are unique");
  assert.equal(v.yieldPerHour("wood", 1), data.yields.wood);
  assert.equal(v.yieldPerHour("wood", 3), Math.round(data.yields.wood * data.yield_growth ** 2));
  assert.equal(v.storeCap("gold", 2), v.yieldPerHour("gold", 2) * data.store_hours);
  const militia = v.militia(1);
  assert.equal(Object.values(militia).reduce((a, b) => a + b, 0), data.guard_base);
  assert.deepEqual(Object.keys(v.militia(5)).sort(), ["archer", "horseman", "spearman", "swordsman"]);
  assert.equal(v.palisade(3), data.palisade_base + 2 * data.palisade_per_level);
  assert.deepEqual([1, 2, 3, 4, 5].map((k) => v.slotsFor(k)), [0, 1, 2, 3, 4]);
});

test("an owned village sends whole units, keeps the rest for later, and stops at its store", () => {
  const info: VillageInfo = { id: "v", name: "Testby", position: [0, 0], level: 1, resource: "gold" };
  const state: VillageState = { id: "v", owner: "Me", guard: {}, taken_at: T0, paid_at: T0 };
  const perHour = v.yieldPerHour("gold", 1);
  const tick = v.collect(info, state, T0 + 20);
  assert.equal(tick.amount, Math.floor(perHour * 20 / HOUR));
  assert.ok(tick.paid_at <= T0 + 20, "time not paid for yet is kept");
  const hour = v.collect(info, state, T0 + HOUR);
  assert.deepEqual(hour, { amount: perHour, paid_at: T0 + HOUR });
  const week = v.collect(info, state, T0 + 7 * 24 * HOUR);
  assert.deepEqual(week, { amount: v.storeCap("gold", 1), paid_at: T0 + 7 * 24 * HOUR });
  assert.equal(v.collect(info, untouched("v"), T0 + HOUR).amount, 0, "the militia send nobody anything");
  assert.equal(v.stock(info, untouched("v"), T0), v.storeCap("gold", 1), "the militia sit on a full store");
});

test("income from villages lands in the castle, up to its storage", () => {
  const p = player("Holder", 2);
  const before = p.castle.resources.gold;
  const out = act(rules, p, { action: "state" }, T0, { villageIncome: { gold: 40 } });
  assert.ok(Math.abs(out.state.castle.resources.gold - (before + 40)) < 1e-6);
  const full = act(rules, p, { action: "state" }, T0, { villageIncome: { gold: 1e9 } });
  assert.equal(full.state.castle.resources.gold, CastleState.fromDict(rules.buildings, full.state.castle).storageCapacity());
});

test("you need a keep with room, and can't attack your own, an ally's, or a village at peace", () => {
  const militia = untouched(first.id);
  const army = { spearman: 10 };
  const low = player("Low", 1, army);
  assert.equal(act(rules, low, { action: "attack_village", village: first.id, army }, T0, { village: target(first, militia) }).error,
    `Your keep must reach level ${v.firstSlotKeep()} to hold a village.`);
  const p = player("Taker", 2, army);
  assert.equal(act(rules, p, { action: "attack_village", village: first.id, army }, T0, { village: target(first, militia, 1) }).error,
    "Your keep can't hold another village yet.");
  assert.equal(act(rules, p, { action: "attack_village", village: first.id, army }, T0).error, "There's no such village.");
  const mine: VillageState = { ...militia, owner: "Taker", taken_at: 1, paid_at: 1 };
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(first, mine) }).error,
    "This village is already yours.");
  const friend: VillageState = { ...militia, owner: "Friend", taken_at: 1, paid_at: 1 };
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(first, friend, 0, true) }).error,
    "This village belongs to your alliance.");
  const fresh: VillageState = { ...friend, taken_at: T0 - 60 };
  assert.equal(act(rules, p, { action: "attack_village", army }, T0, { village: target(first, fresh) }).error,
    "This village just changed hands and is at peace for now.");
  assert.equal(act(rules, p, { action: "attack_village", army: { spearman: 99 } }, T0, { village: target(first, militia) }).error,
    "Your garrison doesn't have that many soldiers.");
});

test("an attack marches out like a raid, and ends your protection only against a player", () => {
  const p = player("Marcher", 2, { spearman: 30 });
  const out = act(rules, p, { action: "attack_village", village: first.id, army: { spearman: 20 } }, T0,
    { village: target(first, untouched(first.id)) });
  assert.equal(out.error, "");
  const r = out.raid!;
  assert.equal(r.village, first.id);
  assert.equal(r.mission, "attack");
  assert.equal(r.defender_name, first.name);
  assert.deepEqual(r.to, first.position);
  assert.ok(Math.abs(r.back - r.depart - 2 * (r.arrive - r.depart)) < 1e-6, "there and back");
  assert.equal(out.state.castle.troops.spearman, 10);
  assert.equal(out.state.protected_until, p.protected_until, "the militia are fair game");
  const owned: VillageState = { ...untouched(first.id), owner: "Other", taken_at: 1, paid_at: 1 };
  const vs = act(rules, p, { action: "attack_village", army: { spearman: 20 } }, T0, { village: target(first, owned) });
  assert.equal(vs.raid!.defender_name, first.name);
  assert.equal(vs.state.protected_until, 0);
});

function raidFrom(p: PlayerState, order: Record<string, unknown>, t: VillageTarget, id = 1): Raid {
  const out = act(rules, p, order, T0, { village: t });
  assert.equal(out.error, "");
  return { ...out.raid!, id };
}

test("beating the militia takes the village and its store, if your keep has room", () => {
  const info = world.villages!.find((x) => x.level === 1)!;
  const p = player("Conqueror", 2, { swordsman: 120 });
  const raid = raidFrom(p, { action: "attack_village", army: { swordsman: 120 } }, target(info, untouched(info.id)));
  const won = resolveVillageRaid(rules, info, untouched(info.id), raid, true);
  assert.equal(won.attackerReport!.winner, "a");
  assert.equal(won.attackerReport!.captured, true);
  assert.equal(won.ownerReport, null, "nobody to tell");
  assert.deepEqual(won.state, { id: info.id, owner: "Conqueror", guard: {}, taken_at: raid.arrive, paid_at: raid.arrive });
  assert.equal(won.loot[info.resource], v.storeCap(info.resource, info.level), "a full store, and they carry it all");
  const noRoom = resolveVillageRaid(rules, info, untouched(info.id), raid, false);
  assert.equal(noRoom.state.owner, "", "the militia stay");
  assert.equal(noRoom.attackerReport!.no_room, true);
  const weak = raidFrom(player("Weakling", 2, { spearman: 3 }), { action: "attack_village", army: { spearman: 3 } },
    target(info, untouched(info.id)));
  const lost = resolveVillageRaid(rules, info, untouched(info.id), weak, true);
  assert.equal(lost.attackerReport!.winner, "b");
  assert.equal(lost.state.owner, "");
  assert.deepEqual(lost.loot, {});
});

test("guards join their village; a village that changed hands sends them home", () => {
  const owned: VillageState = { ...untouched(first.id), owner: "Keeper", guard: { archer: 5 }, taken_at: 1, paid_at: 1 };
  const p = player("Keeper", 2, { archer: 10 });
  const raid = raidFrom(p, { action: "station", army: { archer: 10 } }, target(first, owned));
  assert.equal(raid.mission, "station");
  const joined = resolveVillageRaid(rules, first, owned, raid, true);
  assert.deepEqual(joined.state.guard, { archer: 15 });
  assert.equal(joined.attackerReport, null);
  assert.deepEqual(joined.survivors, {});
  const taken = resolveVillageRaid(rules, first, { ...owned, owner: "Thief" }, raid, true);
  assert.deepEqual(taken.survivors, { archer: 10 });
  assert.equal(taken.attackerReport!.result, "lost");
  assert.equal(act(rules, player("Stranger", 2, { archer: 1 }), { action: "station", army: { archer: 1 } }, T0,
    { village: target(first, owned) }).error, "That village isn't yours.");
});

test("a player's village: guards defend it, the owner is told, and its store goes with it", () => {
  const info = world.villages!.find((x) => x.level === 1)!;
  const owned: VillageState = { id: info.id, owner: "Owner", guard: { spearman: 2 }, taken_at: 1, paid_at: T0 - 2 * HOUR };
  const p = player("Raider", 3, { swordsman: 80 });
  const raid = raidFrom(p, { action: "attack_village", army: { swordsman: 80 } }, target(info, owned));
  const out = resolveVillageRaid(rules, info, owned, raid, true);
  assert.equal(out.attackerReport!.winner, "a");
  assert.equal(out.state.owner, "Raider");
  assert.equal(out.ownerReport!.role, "defender");
  assert.equal(out.ownerReport!.other, "Raider");
  assert.equal(out.attackerReport!.other, "Owner");
  const made = Math.floor(v.yieldPerHour(info.resource, info.level) * (raid.arrive - owned.paid_at) / HOUR);
  assert.equal(out.loot[info.resource], made, "what the village made since the owner was last paid");
  // Arriving during the peace that follows: the army turns back.
  const peace = resolveVillageRaid(rules, info, out.state, { ...raid, id: 2, attacker_name: "Late" }, true);
  assert.equal(peace.attackerReport!.result, "peace");
  assert.deepEqual(peace.survivors, raid.army);
  assert.equal(peace.state, out.state);
  // A strong guard holds, and keeps what is left of it.
  const fort: VillageState = { ...owned, guard: { swordsman: 400 } };
  const held = resolveVillageRaid(rules, info, fort, raid, true);
  assert.equal(held.attackerReport!.winner, "b");
  assert.equal(held.state.owner, "Owner");
  assert.ok(held.state.guard.swordsman < 400 && held.state.guard.swordsman > 0);
});
