// The game server: one Edge Function that every online order goes through.
// The caller must be signed in (Supabase Auth). It loads their player row,
// runs their world up to the server's clock, carries out the order and saves
// the result, so the game never decides anything itself.
//
// POST { "action": "join", "name": "..." }       create your castle on a free spot
// POST { "action": "state" }                     your castle, camps, marches, raids and reports
// POST { "action": "world" }                     other players: name, spot, level, protection
// POST { "action": "leaderboard" }               the mightiest castles, and your own rank
// POST { "action": "place", "type", "cell": [x, y] }
// POST { "action": "upgrade" | "cancel", "id" }
// POST { "action": "move", "id", "cell": [x, y] }
// POST { "action": "recruit", "unit", "amount" }
// POST { "action": "cancel_training", "index" }
// POST { "action": "attack", "camp", "army": { unit: count } }
// POST { "action": "attack_player", "target": "name", "army": { unit: count } }
// POST { "action": "spy", "target": "name" }
// POST { "action": "found_alliance", "name", "tag" }  costs gold (data/alliances.json)
// POST { "action": "alliance" }                  your alliance, its members and requests, invitations, all alliances
// POST { "action": "join_alliance" | "accept_invite" | "decline_invite" | "cancel_request", "id" }
// POST { "action": "leave_alliance" | "disband_alliance" }
// POST { "action": "invite" | "cancel_invite" | "kick", "target": "name" }
// POST { "action": "answer_request", "target": "name", "accept": true }
// POST { "action": "set_role", "target": "name", "role": "leader" | "officer" | "member" }
// POST { "action": "alliance_settings", "open": true, "description": "..." }
//
// Armies sent against players are rows in the raids table. Whenever either
// side sends a request after an army has arrived, the battle is fought on
// the defender's castle as it was at that moment; survivors and loot reach
// the attacker's castle with their first request after the army is back.
// Alliance orders answer with the alliance screen's view (alliances.ts).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import buildings from "../../../data/buildings.json" with { type: "json" };
import units from "../../../data/units.json" with { type: "json" };
import barons from "../../../data/barons.json" with { type: "json" };
import pvpData from "../../../data/pvp.json" with { type: "json" };
import alliancesData from "../../../data/alliances.json" with { type: "json" };
import world from "../../../server/world/world.json" with { type: "json" };
import { makeRules } from "../../../server/rules/load.ts";
import {
  act, castleLevel, checkName, fightRaid, isProtected, might, newPlayer, pickSpot, spyReport,
  type PlayerState, type PvpRules, type Raid, type Target, type World,
} from "./game.ts";
import { allianceView, checkFound, found, handle, type AllianceRules } from "./alliances.ts";
import { DatabaseAllianceStore } from "./alliance_store.ts";

const rules = makeRules(buildings, units, barons);
const pvp = pvpData as PvpRules;
const allianceRules = alliancesData as AllianceRules;
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const store = new DatabaseAllianceStore(admin);
const ALLIANCE_ORDERS = new Set([
  "alliance", "join_alliance", "accept_invite", "decline_invite", "cancel_request", "leave_alliance", "disband_alliance",
  "invite", "cancel_invite", "kick", "answer_request", "set_role", "alliance_settings",
]);
const COLUMNS = "name, home_x, home_y, castle, camps, marches, next_march, protected_until, barons_beaten, version";
const REPORTS_SHOWN = 20;
const RETRIES = 4;
const PLAYERS_SHOWN = 500;
const RANKS_SHOWN = 50;

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function now(): number {
  return Date.now() / 1000;
}

function raidFromRow(r: Row): Raid {
  return {
    id: Number(r.id), attacker_name: r.attacker_name, defender_name: r.defender_name, army: r.army,
    from: [r.from_x, r.from_y], to: [r.to_x, r.to_y], depart: r.depart, arrive: r.arrive, back: r.back,
    state: r.state, survivors: r.survivors, loot: r.loot,
  };
}

async function recentReports(userId: string) {
  const { data } = await admin.from("reports").select("id, at, report").eq("user_id", userId)
    .order("id", { ascending: false }).limit(REPORTS_SHOWN);
  return data ?? [];
}

/** Armies on the move that you sent, or that are coming for you (their size hidden). */
async function activeRaids(userId: string) {
  const { data } = await admin.from("raids").select("*").or(`attacker.eq.${userId},defender.eq.${userId}`)
    .in("state", ["out", "fighting", "home"]).order("arrive");
  return (data ?? []).map((r: Row) => {
    const mine = r.attacker === userId;
    const raid = raidFromRow(r);
    return { ...raid, mine, army: mine ? raid.army : {}, survivors: mine ? raid.survivors : {}, loot: mine ? raid.loot : {} };
  });
}

async function view(userId: string, state: PlayerState, extra: Record<string, unknown> = {}) {
  const [reports, raids] = await Promise.all([recentReports(userId), activeRaids(userId)]);
  return { ok: true, now: now(), ...extra, player: state, raids, reports };
}

/** The columns other players can see, worked out from a player's state. */
function publicColumns(state: PlayerState) {
  return { level: castleLevel(state.castle), might: might(state.castle, pvp) };
}

async function saveReports(userId: string, reports: unknown[]) {
  if (reports.length === 0) return;
  // deno-lint-ignore no-explicit-any
  await admin.from("reports").insert(reports.map((r: any) => ({ user_id: userId, at: r.at, report: r })));
}

/** Fights every battle between players that is due and involves this player. */
async function resolveRaids(userId: string) {
  const { data: due } = await admin.from("raids").select("*").eq("state", "out").lte("arrive", now())
    .or(`attacker.eq.${userId},defender.eq.${userId}`).order("arrive");
  for (const row of due ?? []) {
    // Take the battle, so that no other request fights it as well.
    const { data: claimed } = await admin.from("raids").update({ state: "fighting" })
      .eq("id", row.id).eq("state", "out").select("id");
    if (!claimed || claimed.length === 0) continue;
    const raid = raidFromRow(row);
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const { data: target } = await admin.from("players").select(COLUMNS).eq("user_id", row.defender).maybeSingle();
      if (!target) break;
      const { version, ...stored } = target as PlayerState & { version: number };
      const outcome = fightRaid(rules, pvp, stored, raid);
      const { data: saved } = await admin.from("players")
        .update({ ...outcome.defender, ...publicColumns(outcome.defender), version: version + 1, updated_at: new Date().toISOString() })
        .eq("user_id", row.defender).eq("version", version).select("version");
      if (!saved || saved.length === 0) continue;
      await saveReports(row.defender, [...outcome.campReports, outcome.defenderReport]);
      await saveReports(row.attacker, [outcome.attackerReport]);
      await admin.from("raids").update({ state: "home", survivors: outcome.survivors, loot: outcome.loot }).eq("id", row.id);
      break;
    }
  }
}

/** The other player an order names, with whether they can be attacked now. */
async function findTarget(name: unknown, userId: string): Promise<{ target: Target; row: Row } | null> {
  if (typeof name !== "string" || name.trim() === "") return null;
  const { data } = await admin.from("players").select(`user_id, alliance_id, ${COLUMNS}`)
    .ilike("name", name.trim().replace(/[%_\\]/g, "\\$&")).maybeSingle();
  if (!data) return null;
  const row = data as Row;
  const me = await store.player(userId);
  const ally = row.alliance_id !== null && me !== null && Number(row.alliance_id) === me.alliance_id;
  return {
    target: { name: row.name, home: [row.home_x, row.home_y], protected: isProtected(row as PlayerState, pvp, now()), ally },
    row,
  };
}

/** An alliance's tag from an embedded `alliance:alliances!players_alliance_id_fkey(tag)`, or "". The foreign key
 * is named because players also reach alliances through alliance_pending. */
function tagOf(r: Row): string {
  return r.alliance?.tag ?? "";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply({ ok: false, error: "Use POST." }, 405);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth?.user) return reply({ ok: false, error: "Please sign in again." }, 401);
  const userId = auth.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply({ ok: false, error: "Bad request." }, 400);
  }
  if (body === null || typeof body !== "object" || Array.isArray(body)) return reply({ ok: false, error: "Bad request." }, 400);

  if (body.action === "join") {
    const why = checkName(body.name);
    if (why !== "") return reply({ ok: false, error: why });
    // Another player may take the same spot at the same moment; then try another.
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const { data: homes, error: homesError } = await admin.from("players").select("home_x, home_y");
      if (homesError) return reply({ ok: false, error: "The server couldn't create your castle." }, 500);
      const spot = pickSpot(world as World, (homes ?? []).map((h) => [h.home_x, h.home_y] as [number, number]));
      if (spot === null) return reply({ ok: false, error: "The world is full. Try again later." });
      const state = newPlayer(rules, world as World, String(body.name), now(), spot, pvp);
      const { error } = await admin.from("players").insert({ user_id: userId, ...state, ...publicColumns(state), version: 1 });
      if (!error) return reply(await view(userId, state));
      if (error.code !== "23505") return reply({ ok: false, error: "The server couldn't create your castle." }, 500);
      if (error.message.includes("players_home_key")) continue;
      const taken = error.message.includes("name");
      return reply({ ok: false, error: taken ? "That name is taken." : "You already have a castle." });
    }
    return reply({ ok: false, error: "The server is busy, try again." }, 503);
  }

  if (body.action === "world") {
    const { data, error } = await admin.from("players")
      .select("name, home_x, home_y, level, protected_until, alliance_id, alliance:alliances!players_alliance_id_fkey(tag)")
      .neq("user_id", userId).limit(PLAYERS_SHOWN);
    if (error) return reply({ ok: false, error: "The server couldn't load the map." }, 500);
    const me = await store.player(userId);
    const t = now();
    const players = (data ?? []).map((p: Row) => ({
      name: p.name, home_x: p.home_x, home_y: p.home_y, level: p.level,
      protected: p.protected_until > t && p.level < pvp.protection_until_keep,
      tag: tagOf(p), ally: p.alliance_id !== null && me !== null && Number(p.alliance_id) === me.alliance_id,
    }));
    return reply({ ok: true, now: t, error: "", players });
  }

  if (body.action === "leaderboard") {
    const shown = "name, level, might, barons_beaten, alliance:alliances!players_alliance_id_fkey(tag)";
    const { data, error } = await admin.from("players").select(shown)
      .order("might", { ascending: false }).order("barons_beaten", { ascending: false }).order("name")
      .limit(RANKS_SHOWN);
    const { data: mine } = await admin.from("players").select(shown).eq("user_id", userId).maybeSingle();
    const flat = (r: Row) => ({ name: r.name, level: r.level, might: r.might, barons_beaten: r.barons_beaten, tag: tagOf(r) });
    const me = mine ? flat(mine) : null;
    if (error) return reply({ ok: false, error: "The server couldn't load the leaderboard." }, 500);
    let rank = 0;
    if (me) {
      const { count } = await admin.from("players").select("user_id", { count: "exact", head: true }).gt("might", me.might);
      rank = (count ?? 0) + 1;
    }
    const { count: total } = await admin.from("players").select("user_id", { count: "exact", head: true });
    return reply({ ok: true, now: now(), error: "", result: { players: (data ?? []).map(flat), me, rank, total: total ?? 0 } });
  }

  if (typeof body.action === "string" && ALLIANCE_ORDERS.has(body.action)) {
    const error = await handle(store, allianceRules, userId, body, now());
    return reply({ ok: true, now: now(), error, result: await allianceView(store, allianceRules, userId) });
  }

  // Founding an alliance: create it, then pay for it from the castle below
  // (and take it back if the castle can't pay).
  let founded: number | null = null;
  if (body.action === "found_alliance") {
    const why = await checkFound(store, userId, body);
    if (why !== "") return reply({ ok: true, now: now(), error: why, result: await allianceView(store, allianceRules, userId) });
    const made = await found(store, userId, body, now());
    if (typeof made === "string") {
      return reply({ ok: true, now: now(), error: made, result: await allianceView(store, allianceRules, userId) });
    }
    founded = made;
  }

  await resolveRaids(userId);

  let target: { target: Target; row: Row } | null = null;
  if (body.action === "attack_player" || body.action === "spy") target = await findTarget(body.target, userId);

  // Armies back from attacking players; take them so no other request adds them too.
  const { data: back } = await admin.from("raids").select("*").eq("attacker", userId).eq("state", "home").lte("back", now());
  const homecomings: Raid[] = [];
  for (const row of back ?? []) {
    const { data: claimed } = await admin.from("raids").update({ state: "done" }).eq("id", row.id).eq("state", "home").select("id");
    if (claimed && claimed.length > 0) homecomings.push(raidFromRow(row));
  }

  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row, error } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (error) return reply({ ok: false, error: "The server couldn't load your castle." }, 500);
    if (!row) {
      if (founded !== null) await store.remove(founded);
      return reply({ ok: false, error: "No castle yet.", needs_join: true });
    }
    const { version, ...stored } = row as PlayerState & { version: number };
    const t = now();
    const outcome = act(rules, stored, body, t, { pvp, target: target?.target, homecomings, alliances: allianceRules });
    // Save only if nobody else changed the row meanwhile; otherwise start over.
    const { data: saved, error: saveError } = await admin.from("players")
      .update({ ...outcome.state, ...publicColumns(outcome.state), version: version + 1, updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saveError) {
      if (founded !== null) await store.remove(founded);
      return reply({ ok: false, error: "The server couldn't save your castle." }, 500);
    }
    if (!saved || saved.length === 0) continue;
    await saveReports(userId, outcome.reports);
    let result = outcome.result ?? null;
    if (outcome.raid && target) {
      const r = outcome.raid;
      await admin.from("raids").insert({
        attacker: userId, defender: target.row.user_id, attacker_name: r.attacker_name, defender_name: r.defender_name,
        army: r.army, from_x: r.from[0], from_y: r.from[1], to_x: r.to[0], to_y: r.to[1],
        depart: r.depart, arrive: r.arrive, back: r.back,
      });
    }
    if (body.action === "spy" && outcome.error === "" && target) {
      result = spyReport(rules, pvp, target.row as PlayerState, t);
    }
    if (founded !== null) {
      if (outcome.error !== "") await store.remove(founded);
      result = await allianceView(store, allianceRules, userId);
    }
    return reply(await view(userId, outcome.state, { error: outcome.error, result }));
  }
  if (founded !== null) await store.remove(founded);
  return reply({ ok: false, error: "The server is busy, try again." }, 503);
});
