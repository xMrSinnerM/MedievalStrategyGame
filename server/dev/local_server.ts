// A stand-in for the Supabase project, for trying the online game without
// the internet: the same sign-up/sign-in endpoints as Supabase Auth and the
// same game function (game.ts), keeping players in memory. Accounts are
// confirmed at once and nothing is saved when it stops.
//
//   node server/dev/local_server.ts            (listens on port 54321)
//   START_TROOPS='{"spearman":60}' node server/dev/local_server.ts   (castles start with soldiers)
//   PROTECTION_HOURS=0 node server/dev/local_server.ts              (no beginner protection)
//   START_KEEP=2 START_RESOURCES='{"gold":1000}' node server/dev/local_server.ts   (bigger starting castles)
//   EVENTS_OFFSET_HOURS=30 node server/dev/local_server.ts         (timed events as if 30 hours later)
//   godot --path . -- --online-url=http://127.0.0.1:54321

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { effectAt, eventsView, lastInvasion, type EventRules } from "../rules/events.ts";
import {
  act, castleLevel, checkName, fightRaid, isProtected, might, newPlayer, pickSpot, spyReport,
  type PlayerState, type PvpRules, type Raid, type Target, type World,
} from "../../supabase/functions/game/game.ts";
import {
  allianceView, checkFound, found, handle, MemoryAllianceStore, type AllianceRules,
} from "../../supabase/functions/game/alliances.ts";
import { chatView, MemoryChatStore, send as sendChat, type Speaker } from "../../supabase/functions/game/chat.ts";
import { deliver, recall, type Aid, type AidRules } from "../../supabase/functions/game/aid.ts";
import { invade } from "../../supabase/functions/game/invasion.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const allianceRules: AllianceRules = json("data/alliances.json");
const aidRules: AidRules = json("data/aid.json");
const eventRules: EventRules = json("data/events.json");
// For testing: run the event calendar this many hours ahead, to see an event on.
const EVENTS_OFFSET = Number(process.env.EVENTS_OFFSET_HOURS ?? 0) * 3600;
rules.barons.lootFactor = (t) => effectAt(eventRules, t + EVENTS_OFFSET, "baron_loot");
// For testing: hours of beginner protection for new castles (data/pvp.json's by default).
if (process.env.PROTECTION_HOURS !== undefined) pvp.protection_hours = Number(process.env.PROTECTION_HOURS);
const PORT = Number(process.env.PORT ?? 54321);
const TOKEN_LIFE = Number(process.env.TOKEN_LIFE ?? 3600);
// For testing: soldiers every new castle starts with, as JSON ({"spearman": 50}).
const START_TROOPS = JSON.parse(process.env.START_TROOPS ?? "{}");
// For testing: the keep level and resources new castles start with.
const START_KEEP = Number(process.env.START_KEEP ?? 0);
const START_RESOURCES = JSON.parse(process.env.START_RESOURCES ?? "{}");

const users = new Map<string, { id: string; password: string }>();
const tokens = new Map<string, { user: string; expires: number }>();
const refreshTokens = new Map<string, string>();
const players = new Map<string, PlayerState>();
const reports: { id: number; user: string; at: number; report: unknown }[] = [];
let nextReport = 1;
const raids: (Raid & { attacker: string; defender: string })[] = [];
let nextRaid = 1;
const aid: (Aid & { sender: string; receiver: string; state: "out" | "done" })[] = [];
let nextAid = 1;
const store = new MemoryAllianceStore(() => new Map([...players].map(([id, p]) => [id,
  { name: p.name, level: castleLevel(p.castle), might: might(p.castle, pvp) }])));
const chat = new MemoryChatStore();
const ALLIANCE_ORDERS = new Set([
  "alliance", "join_alliance", "accept_invite", "decline_invite", "cancel_request", "leave_alliance", "disband_alliance",
  "invite", "cancel_invite", "kick", "answer_request", "set_role", "alliance_settings",
]);

/** A player's alliance tag, or "". */
function tagOf(user: string): string {
  const m = store.membership.get(user);
  return m === undefined ? "" : store.alliancesById.get(m.alliance_id)?.tag ?? "";
}

function allies(a: string, b: string): boolean {
  const x = store.membership.get(a);
  return x !== undefined && x.alliance_id === store.membership.get(b)?.alliance_id;
}

function speaker(user: string): Speaker {
  return { user, name: players.get(user)!.name, tag: tagOf(user), alliance_id: store.membership.get(user)?.alliance_id ?? null };
}

const now = () => Date.now() / 1000;

function send(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readBody(req: IncomingMessage): Promise<Record<string, unknown> | null> {
  let text = "";
  for await (const chunk of req) text += chunk;
  try {
    const body = JSON.parse(text);
    return body !== null && typeof body === "object" && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

function session(email: string) {
  const user = users.get(email)!;
  const access = randomUUID();
  const refresh = randomUUID();
  tokens.set(access, { user: user.id, expires: now() + TOKEN_LIFE });
  refreshTokens.set(refresh, email);
  return { access_token: access, token_type: "bearer", expires_in: TOKEN_LIFE, expires_at: Math.floor(now() + TOKEN_LIFE),
    refresh_token: refresh, user: { id: user.id, email } };
}

function view(user: string, state: PlayerState, extra: Record<string, unknown> = {}) {
  const mine = reports.filter((r) => r.user === user).slice(-20).reverse().map(({ id, at, report }) => ({ id, at, report }));
  const moving = raids.filter((r) => (r.attacker === user || r.defender === user) && r.state !== "done")
    .map(({ attacker, defender: _d, ...r }) => {
      const own = attacker === user;
      return { ...r, mine: own, army: own ? r.army : {}, survivors: own ? r.survivors : {}, loot: own ? r.loot : {} };
    });
  const helping = aid.filter((a) => (a.sender === user || a.receiver === user) && a.state === "out")
    .sort((a, b) => a.arrive - b.arrive).map(({ sender, receiver: _r, state: _s, ...a }) => ({ ...a, mine: sender === user }));
  return { ok: true, now: now(), ...extra, player: state, raids: moving, aid: helping, reports: mine,
    events: shifted(eventsView(eventRules, now() + EVENTS_OFFSET)) };
}

/** The event view with times moved back from the shifted calendar to the real clock. */
function shifted(v: ReturnType<typeof eventsView>) {
  const back = (e: { start: number; end: number }) => ({ ...e, start: e.start - EVENTS_OFFSET, end: e.end - EVENTS_OFFSET });
  return { active: v.active.map(back), upcoming: v.upcoming.map(back) };
}

function report(user: string, r: { at: number }) {
  reports.push({ id: nextReport++, user, at: r.at, report: r });
}

// The same as resolveAid() in index.ts, without the database.
function resolveAid(user: string) {
  for (const cart of aid.filter((a) => a.kind === "resources" && a.state === "out" && a.arrive <= now() &&
    (a.sender === user || a.receiver === user)).sort((a, b) => a.arrive - b.arrive)) {
    cart.state = "done";
    const receiver = players.get(cart.receiver);
    if (receiver === undefined) continue;
    const out = deliver(rules, receiver, cart);
    players.set(cart.receiver, out.receiver);
    for (const r of out.campReports) report(cart.receiver, r);
    report(cart.receiver, out.receiverReport);
    report(cart.sender, out.senderReport);
  }
}

function helpersAt(user: string, t: number) {
  return aid.filter((a) => a.receiver === user && a.kind === "troops" && a.state === "out" && a.arrive <= t && t < a.leave);
}

// The same as resolveRaids() in index.ts, without the database.
function resolveRaids(user: string) {
  for (const raid of raids.filter((r) => r.state === "out" && r.arrive <= now() && (r.attacker === user || r.defender === user))
    .sort((a, b) => a.arrive - b.arrive)) {
    const defender = players.get(raid.defender);
    if (defender === undefined) continue;
    const helpers = helpersAt(raid.defender, raid.arrive);
    const outcome = fightRaid(rules, pvp, defender, raid, helpers.map((h) => h.army));
    players.set(raid.defender, outcome.defender);
    for (const r of outcome.campReports) report(raid.defender, r);
    if (helpers.length > 0) outcome.defenderReport.helped_by = [...new Set(helpers.map((h) => h.sender_name))];
    report(raid.defender, outcome.defenderReport);
    report(raid.attacker, outcome.attackerReport);
    Object.assign(raid, { state: "home", survivors: outcome.survivors, loot: outcome.loot });
    for (const [i, h] of helpers.entries()) {
      const left = outcome.helpers[i];
      const lost: Record<string, number> = {};
      for (const unit of Object.keys(h.army)) if (h.army[unit] - (left[unit] ?? 0) > 0) lost[unit] = h.army[unit] - (left[unit] ?? 0);
      h.army = left;
      if (Object.keys(left).length === 0) h.state = "done";
      report(h.sender, { kind: "aid", event: "defended", name: h.receiver_name, at: raid.arrive, attacker: raid.attacker_name,
        held: outcome.attackerReport.winner === "b", lost } as { at: number });
    }
  }
}

function findTarget(name: unknown, me: string): { target: Target; user: string } | undefined {
  if (typeof name !== "string") return undefined;
  for (const [id, p] of players) {
    if (p.name.toLowerCase() === name.trim().toLowerCase()) {
      return { target: { name: p.name, home: [p.home_x, p.home_y], protected: isProtected(p, pvp, now()), ally: allies(me, id) },
        user: id };
    }
  }
  return undefined;
}

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://localhost:${PORT}`);
  if (req.method !== "POST") return send(res, 405, { error: "Use POST." });
  const body = await readBody(req);
  if (body === null) return send(res, 400, { msg: "Bad request." });

  if (url.pathname === "/auth/v1/signup") {
    const email = String(body.email ?? "").toLowerCase();
    const password = String(body.password ?? "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return send(res, 400, { error_code: "validation_failed", msg: "Unable to validate email address: invalid format" });
    if (password.length < 6) return send(res, 422, { error_code: "weak_password", msg: "Password should be at least 6 characters." });
    if (users.has(email)) return send(res, 422, { error_code: "user_already_exists", msg: "User already registered" });
    users.set(email, { id: randomUUID(), password });
    return send(res, 200, session(email));
  }
  if (url.pathname === "/auth/v1/token") {
    if (url.searchParams.get("grant_type") === "password") {
      const email = String(body.email ?? "").toLowerCase();
      if (users.get(email)?.password !== body.password) return send(res, 400, { error_code: "invalid_credentials", msg: "Invalid login credentials" });
      return send(res, 200, session(email));
    }
    if (url.searchParams.get("grant_type") === "refresh_token") {
      const email = refreshTokens.get(String(body.refresh_token ?? ""));
      if (email === undefined) return send(res, 400, { error_code: "refresh_token_not_found", msg: "Invalid Refresh Token: Refresh Token Not Found" });
      refreshTokens.delete(String(body.refresh_token));
      return send(res, 200, session(email));
    }
  }
  if (url.pathname === "/functions/v1/game") {
    const token = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
    const auth = tokens.get(token);
    if (auth === undefined || auth.expires < now()) return send(res, 401, { code: 401, message: "Invalid JWT" });
    const user = auth.user;
    if (body.action === "join") {
      const why = checkName(body.name);
      if (why !== "") return send(res, 200, { ok: false, error: why });
      if (players.has(user)) return send(res, 200, { ok: false, error: "You already have a castle." });
      const taken = [...players.values()].some((p) => p.name.toLowerCase() === String(body.name).trim().toLowerCase());
      if (taken) return send(res, 200, { ok: false, error: "That name is taken." });
      const spot = pickSpot(world, [...players.values()].map((p) => [p.home_x, p.home_y] as [number, number]));
      if (spot === null) return send(res, 200, { ok: false, error: "The world is full. Try again later." });
      const state = newPlayer(rules, world, String(body.name), now(), spot, pvp);
      state.castle.troops = { ...START_TROOPS };
      Object.assign(state.castle.resources, START_RESOURCES);
      const keep = state.castle.buildings.find((b) => b.type === "keep");
      if (keep && START_KEEP > 0) keep.level = START_KEEP;
      const placed = invade(state, eventRules, world, now(), EVENTS_OFFSET);
      players.set(user, placed);
      return send(res, 200, view(user, placed));
    }
    if (body.action === "world") {
      const others = [...players.entries()].filter(([id]) => id !== user)
        .map(([id, p]) => ({ name: p.name, home_x: p.home_x, home_y: p.home_y, level: castleLevel(p.castle),
          protected: isProtected(p, pvp, now()), tag: tagOf(id), ally: allies(user, id) }));
      return send(res, 200, { ok: true, now: now(), error: "", players: others });
    }
    if (body.action === "leaderboard") {
      const all = [...players.entries()].map(([id, p]) => ({ id, name: p.name, level: castleLevel(p.castle),
        might: might(p.castle, pvp), barons_beaten: p.barons_beaten ?? 0, tag: tagOf(id) }))
        .sort((a, b) => b.might - a.might || b.barons_beaten - a.barons_beaten || a.name.localeCompare(b.name));
      const strip = ({ id: _id, ...row }: (typeof all)[number]) => row;
      const mine = all.find((r) => r.id === user);
      const rank = mine ? all.filter((r) => r.might > mine.might).length + 1 : 0;
      return send(res, 200, { ok: true, now: now(), error: "",
        result: { players: all.slice(0, 50).map(strip), me: mine ? strip(mine) : null, rank, total: all.length } });
    }
    if (body.action === "event_board") {
      const inv = lastInvasion(eventRules, now() + EVENTS_OFFSET);
      const key = inv === undefined ? -1 : inv.start - EVENTS_OFFSET;
      const all = [...players.entries()].filter(([, p]) => p.event_key === key && (p.event_points ?? 0) > 0)
        .map(([id, p]) => ({ id, name: p.name, points: p.event_points, tag: tagOf(id) }))
        .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
      const strip = ({ id: _id, ...row }: (typeof all)[number]) => row;
      const mine = all.find((r) => r.id === user);
      const rank = mine ? all.filter((r) => r.points > mine.points).length + 1 : 0;
      return send(res, 200, { ok: true, now: now(), error: "", result: {
        event: inv === undefined ? null : shifted({ active: [inv], upcoming: [] }).active[0],
        players: all.slice(0, 50).map(strip), me: mine ? strip(mine) : null, rank, total: all.length } });
    }
    if (!players.has(user)) return send(res, 200, { ok: false, error: "No castle yet.", needs_join: true });
    if (body.action === "chat" || body.action === "chat_send") {
      const error = body.action === "chat_send" ? await sendChat(chat, speaker(user), body, now()) : "";
      return send(res, 200, { ok: true, now: now(), error, result: await chatView(chat, speaker(user), body.after) });
    }
    if (typeof body.action === "string" && ALLIANCE_ORDERS.has(body.action)) {
      const error = await handle(store, allianceRules, user, body, now());
      return send(res, 200, { ok: true, now: now(), error, result: await allianceView(store, allianceRules, user) });
    }
    // The same as founding in index.ts: create the alliance, then pay for it.
    let founded: number | null = null;
    if (body.action === "found_alliance") {
      const why = await checkFound(store, user, body);
      const made = why === "" ? await found(store, user, body, now()) : why;
      if (typeof made === "string") {
        return send(res, 200, { ok: true, now: now(), error: made, result: await allianceView(store, allianceRules, user) });
      }
      founded = made;
    }
    // The same as recall_defenders in index.ts.
    let recalled = "";
    if (body.action === "recall_defenders") {
      const a = aid.find((x) => x.id === Number(body.id) && x.sender === user && x.kind === "troops" && x.state === "out");
      const times = a === undefined ? "There are no such defenders." : recall(a, now());
      if (typeof times === "string") recalled = times;
      else Object.assign(a!, times);
      body.action = "state";
    }
    resolveAid(user);
    resolveRaids(user);
    const target = ["attack_player", "spy", "send_resources", "send_defenders"].includes(String(body.action))
      ? findTarget(body.target, user) : undefined;
    const homecomings = [
      ...raids.filter((r) => r.attacker === user && r.state === "home" && r.back <= now()),
      ...aid.filter((a) => a.sender === user && a.kind === "troops" && a.state === "out" && a.back <= now())
        .map((a) => ({ ...a, survivors: a.army, loot: {} })),
    ];
    for (const r of raids) if (r.attacker === user && r.state === "home" && r.back <= now()) r.state = "done";
    for (const a of aid) if (a.sender === user && a.kind === "troops" && a.state === "out" && a.back <= now()) a.state = "done";
    const t = now();
    const outcome = act(rules, players.get(user)!, body, t,
      { pvp, target: target?.target, homecomings, alliances: allianceRules, aid: aidRules,
        events: { rules: eventRules, world, offset: EVENTS_OFFSET } });
    players.set(user, outcome.state);
    for (const r of outcome.reports) report(user, r);
    if (outcome.raid && target) raids.push({ ...outcome.raid, id: nextRaid++, attacker: user, defender: target.user });
    if (outcome.aid && target) aid.push({ ...outcome.aid, id: nextAid++, sender: user, receiver: target.user, state: "out" });
    let result = outcome.result ?? null;
    if (body.action === "spy" && outcome.error === "" && target) {
      result = spyReport(rules, pvp, players.get(target.user)!, t, helpersAt(target.user, t).map((h) => h.army));
    }
    if (founded !== null) {
      if (outcome.error !== "") await store.remove(founded);
      result = await allianceView(store, allianceRules, user);
    }
    return send(res, 200, view(user, outcome.state, { error: recalled || outcome.error, result }));
  }
  send(res, 404, { msg: "Not found" });
}).listen(PORT, "127.0.0.1", () => console.log(`Local game server on http://127.0.0.1:${PORT}`));
