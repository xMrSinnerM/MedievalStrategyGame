// Alliances (supabase/functions/game/alliances.ts) with the in-memory store.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, newPlayer, type World } from "../../supabase/functions/game/game.ts";
import {
  allianceView, checkAllianceName, checkFound, found, handle, MemoryAllianceStore, type AllianceRules,
} from "../../supabase/functions/game/alliances.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const ar: AllianceRules = json("data/alliances.json");
const T0 = 1_000_000;

function setup(...names: string[]) {
  const players = new Map(names.map((n) => [n.toLowerCase(), { name: n, level: 3, might: 100 }]));
  return new MemoryAllianceStore(() => players);
}

async function make(store: MemoryAllianceStore, user: string, name: string, tag: string): Promise<number> {
  const req = { action: "found_alliance", name, tag };
  assert.equal(await checkFound(store, user, req), "");
  const id = await found(store, user, req, T0);
  assert.equal(typeof id, "number");
  return id as number;
}

test("alliance names and tags", () => {
  assert.equal(checkAllianceName("Knights of Oak", "KNO"), "");
  assert.equal(checkAllianceName("ab", "KN"), "Alliance names are 3 to 24 characters long.");
  assert.equal(checkAllianceName("Knights <b>", "KN"), "Use letters, numbers, spaces, ' _ and - only.");
  assert.equal(checkAllianceName("Knights", "K"), "Tags are 2 to 4 letters or numbers.");
  assert.equal(checkAllianceName("Knights", "K N"), "Tags are 2 to 4 letters or numbers.");
  assert.equal(checkAllianceName(5, "KN"), "Choose a name and a tag.");
});

test("founding costs gold and needs a keep level", () => {
  let p = newPlayer(rules, world, "Valentin", T0);
  let out = act(rules, p, { action: "found_alliance" }, T0, { alliances: ar });
  assert.equal(out.error, `Founding an alliance needs keep level ${ar.found_keep}.`);
  p.castle.buildings.find((b) => b.type === "keep")!.level = ar.found_keep;
  p.castle.resources.gold = 1000;
  out = act(rules, p, { action: "found_alliance" }, T0, { alliances: ar });
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.gold), 1000 - ar.found_cost.gold);
  p.castle.resources.gold = 10;
  out = act(rules, p, { action: "found_alliance" }, T0, { alliances: ar });
  assert.equal(out.error, "Not enough gold to found an alliance.");
  assert.equal(act(rules, p, { action: "found_alliance" }, T0).error, "Unknown order.");
});

test("found, join an open alliance, and names and tags stay unique", async () => {
  const s = setup("Ann", "Bob", "Cid");
  const id = await make(s, "ann", "Oak Knights", "oak");
  assert.equal(s.alliancesById.get(id)!.tag, "OAK");
  assert.equal(await checkFound(s, "ann", { name: "Second", tag: "SEC" }), "Leave your alliance first.");
  assert.equal(await found(s, "bob", { name: "oak knights", tag: "XX" }, T0), "That alliance name is taken.");
  assert.equal(await found(s, "bob", { name: "Other", tag: "Oak" }, T0), "That tag is taken.");
  assert.equal(await handle(s, ar, "bob", { action: "join_alliance", id }, T0), "");
  const v = await allianceView(s, ar, "bob");
  assert.equal(v.alliance?.name, "Oak Knights");
  assert.equal(v.alliance?.role, "member");
  assert.deepEqual(v.members.map((m) => [m.name, m.role]), [["Ann", "leader"], ["Bob", "member"]]);
  assert.equal(v.alliances[0].members, 2);
  assert.equal(v.alliances[0].might, 200);
  assert.equal(await handle(s, ar, "bob", { action: "kick", target: "Ann" }, T0), "Only the leader and officers can do that.");
});

test("a closed alliance takes requests, and officers answer them", async () => {
  const s = setup("Ann", "Bob", "Cid");
  const id = await make(s, "ann", "Oak Knights", "OAK");
  assert.equal(await handle(s, ar, "ann", { action: "alliance_settings", open: false, description: " Hello " }, T0), "");
  assert.equal(s.alliancesById.get(id)!.description, "Hello");
  assert.equal(await handle(s, ar, "bob", { action: "join_alliance", id }, T0), "");
  assert.equal((await s.player("bob"))!.alliance_id, null, "only asked");
  assert.deepEqual((await allianceView(s, ar, "bob")).asked.map((a) => a.tag), ["OAK"]);
  assert.deepEqual((await allianceView(s, ar, "ann")).requests.map((r) => r.name), ["Bob"]);
  assert.equal(await handle(s, ar, "ann", { action: "answer_request", target: "bob", accept: true }, T0), "");
  assert.equal((await s.player("bob"))!.alliance_id, id);
  assert.equal(s.pendingList.length, 0);
  assert.equal(await handle(s, ar, "cid", { action: "join_alliance", id }, T0), "");
  assert.equal(await handle(s, ar, "ann", { action: "answer_request", target: "Cid", accept: false }, T0), "");
  assert.equal((await s.player("cid"))!.alliance_id, null);
  assert.equal(await handle(s, ar, "ann", { action: "answer_request", target: "Cid", accept: true }, T0), "That request is gone.");
});

test("invitations", async () => {
  const s = setup("Ann", "Bob", "Cid");
  const id = await make(s, "ann", "Oak Knights", "OAK");
  await handle(s, ar, "ann", { action: "alliance_settings", open: false }, T0);
  assert.equal(await handle(s, ar, "ann", { action: "invite", target: "Nobody" }, T0), "There's no player by that name.");
  assert.equal(await handle(s, ar, "ann", { action: "invite", target: "bob" }, T0), "");
  assert.deepEqual((await allianceView(s, ar, "bob")).invites.map((i) => i.name), ["Oak Knights"]);
  assert.deepEqual((await allianceView(s, ar, "ann")).invited.map((i) => i.name), ["Bob"]);
  // An invitation lets you into a closed alliance.
  assert.equal(await handle(s, ar, "bob", { action: "accept_invite", id }, T0), "");
  assert.equal((await s.player("bob"))!.role, "member");
  assert.equal(await handle(s, ar, "ann", { action: "invite", target: "Bob" }, T0), "Bob is in your alliance already.");
  assert.equal(await handle(s, ar, "ann", { action: "invite", target: "Cid" }, T0), "");
  assert.equal(await handle(s, ar, "cid", { action: "decline_invite", id }, T0), "");
  assert.equal(await handle(s, ar, "cid", { action: "accept_invite", id }, T0), "That invitation is gone.");
  // Asking to join after you asked is the same as accepting.
  await handle(s, ar, "cid", { action: "join_alliance", id }, T0);
  assert.equal(await handle(s, ar, "ann", { action: "invite", target: "Cid" }, T0), "");
  assert.equal((await s.player("cid"))!.alliance_id, id);
});

test("roles, removing members and leaving", async () => {
  const s = setup("Ann", "Bob", "Cid", "Dan");
  const id = await make(s, "ann", "Oak Knights", "OAK");
  for (const u of ["bob", "cid", "dan"]) await handle(s, ar, u, { action: "join_alliance", id }, T0 + 1);
  assert.equal(await handle(s, ar, "ann", { action: "set_role", target: "Cid", role: "officer" }, T0), "");
  assert.equal(await handle(s, ar, "cid", { action: "set_role", target: "Bob", role: "officer" }, T0), "Only the leader can change roles.");
  assert.equal(await handle(s, ar, "ann", { action: "set_role", target: "Bob", role: "king" }, T0), "Unknown role.");
  assert.equal(await handle(s, ar, "cid", { action: "kick", target: "Ann" }, T0), "Officers can only remove members.");
  assert.equal(await handle(s, ar, "cid", { action: "kick", target: "Dan" }, T0), "");
  assert.equal((await s.player("dan"))!.alliance_id, null);
  // When the leader leaves, an officer takes over.
  assert.equal(await handle(s, ar, "ann", { action: "leave_alliance" }, T0), "");
  assert.equal((await s.player("cid"))!.role, "leader");
  assert.equal((await s.player("ann"))!.alliance_id, null);
  // Handing over leadership makes the old leader an officer.
  assert.equal(await handle(s, ar, "cid", { action: "set_role", target: "Bob", role: "leader" }, T0), "");
  assert.equal((await s.player("bob"))!.role, "leader");
  assert.equal((await s.player("cid"))!.role, "officer");
  // The last one out closes the alliance.
  await handle(s, ar, "cid", { action: "leave_alliance" }, T0);
  await handle(s, ar, "bob", { action: "leave_alliance" }, T0);
  assert.equal(s.alliancesById.size, 0);
});

test("full alliances and disbanding", async () => {
  const names = Array.from({ length: ar.max_members + 1 }, (_, i) => `Player${i}`);
  const s = setup(...names);
  const id = await make(s, "player0", "Big Host", "BIG");
  for (let i = 1; i < ar.max_members; i++) assert.equal(await handle(s, ar, `player${i}`, { action: "join_alliance", id }, T0), "");
  assert.equal(await handle(s, ar, `player${ar.max_members}`, { action: "join_alliance", id }, T0), "That alliance is full.");
  assert.equal(await handle(s, ar, "player1", { action: "disband_alliance" }, T0), "Only the leader and officers can do that.");
  assert.equal(await handle(s, ar, "player0", { action: "disband_alliance" }, T0), "");
  assert.equal(s.membership.size, 0);
});

test("allies can't attack or spy on each other", () => {
  const p = newPlayer(rules, world, "Ann", T0);
  p.castle.troops = { spearman: 10 };
  p.castle.resources.gold = 500;
  const ally = { name: "Bob", home: [100, 100] as [number, number], protected: false, ally: true };
  assert.equal(act(rules, p, { action: "attack_player", target: "Bob", army: { spearman: 5 } }, T0, { target: ally }).error,
    "You can't attack a member of your own alliance.");
  assert.equal(act(rules, p, { action: "spy", target: "Bob" }, T0, { target: ally }).error, "No need to spy on your own alliance.");
});
