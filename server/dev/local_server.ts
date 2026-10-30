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
//   ADMINS=me@example.com node server/dev/local_server.ts           (these accounts get the owner's tools)
//   WAR_DAYS=0.01 node server/dev/local_server.ts                    (alliance war seasons this many days long)
//   godot --path . -- --online-url=http://127.0.0.1:54321

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { nearestSpot } from "../rules/outposts.ts";
import { CapitalRules, rulesFor, settled, untouched, type VillageInfo, type VillageState } from "../rules/villages.ts";
import { effectAt, eventsView, lastHorde, lastInvasion, withOverrides, type EventOverride, type EventRules } from "../rules/events.ts";
import { CastleState } from "../rules/castle_state.ts";
import {
  act, castleLevel, checkName, fightRaid, isProtected, might, newPlayer, pickSpot, spyReport,
  type PlayerState, type PvpRules, type Raid, type Target, type World,
} from "../../supabase/functions/game/game.ts";
import {
  allianceView, checkFound, found, handle, MemoryAllianceStore, type AllianceRules,
} from "../../supabase/functions/game/alliances.ts";
import { chatView, MemoryChatStore, send as sendChat, type Speaker } from "../../supabase/functions/game/chat.ts";
import { deliver, recall, type Aid, type AidRules } from "../../supabase/functions/game/aid.ts";
import { goingRates, type MarketReport, type MarketRules, type Offer } from "../../supabase/functions/game/market.ts";
import { invade } from "../../supabase/functions/game/invasion.ts";
import { hordeArrives, prizeFor } from "../../supabase/functions/game/horde.ts";
import {
  captureEntry, checkClaim, defenceEntry, givePrize, holdDue, holdEntries, lastSeason, seasonAt, standings, warBoard,
  type WarAlliance, type WarEntry, type WarRules,
} from "../../supabase/functions/game/wars.ts";
import { capitalBoost, resolveVillageRaid, type VillageTarget } from "../../supabase/functions/game/villages.ts";
import type { QuestRules } from "../rules/quests.ts";
import type { AchievementRules } from "../rules/achievements.ts";
import type { LoginRules } from "../rules/login.ts";
import type { ChestRules } from "../rules/chests.ts";
import { allianceStandings, placeIn, renown, seasonColumns, seasonEnd, seasonKey, type SeasonRules } from "../rules/seasons.ts";
import {
  adminEvents, checkGift, giftReport, giveCastle, NOT_ADMIN, startEvent, stopEvent, type AdminLogEntry,
} from "../../supabase/functions/game/admin.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"), json("data/gear.json"),
  json("data/outposts.json"), json("data/villages.json"), json("data/capitals.json"), json("data/fortresses.json"),
  json("data/horde.json"));
const world: World = json("server/world/world.json");
// The resource villages and the capitals (the towns), kept the same way.
const PLACES: VillageInfo[] = [...(world.villages ?? []), ...(world.capitals ?? [])];
const pvp: PvpRules = json("data/pvp.json");
const allianceRules: AllianceRules = json("data/alliances.json");
const aidRules: AidRules = json("data/aid.json");
const marketRules: MarketRules = json("data/market.json");
const eventRules0: EventRules = json("data/events.json");
const questRules: QuestRules = json("data/quests.json");
const warRules: WarRules = json("data/wars.json");
// For testing: shorter alliance war seasons.
if (process.env.WAR_DAYS !== undefined) warRules.days = Number(process.env.WAR_DAYS);
const achievementRules: AchievementRules = json("data/achievements.json");
const loginRules: LoginRules = json("data/login.json");
const seasonRules: SeasonRules = json("data/seasons.json");
const chestRules: ChestRules = json("data/chests.json");
// The calendar with the owner's changes (kept on the shifted clock below).
let eventRules: EventRules = eventRules0;
// For testing: run the event calendar this many hours ahead, to see an event on.
const EVENTS_OFFSET = Number(process.env.EVENTS_OFFSET_HOURS ?? 0) * 3600;
rules.barons.lootFactor = (t) => effectAt(eventRules, t + EVENTS_OFFSET, "baron_loot");
// For testing: accounts (by email) that get the owner's tools, comma separated.
const ADMINS = new Set((process.env.ADMINS ?? "").split(",").map((e) => e.trim().toLowerCase()).filter((e) => e !== ""));
const adminLog: AdminLogEntry[] = [];
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
const isAdmin = (user: string) => [...users].some(([email, u]) => u.id === user && ADMINS.has(email));
const tokens = new Map<string, { user: string; expires: number }>();
const refreshTokens = new Map<string, string>();
const players = new Map<string, PlayerState>();
const reports: { id: number; user: string; at: number; report: unknown }[] = [];
let nextReport = 1;
const raids: (Raid & { attacker: string; defender: string | null })[] = [];
let nextRaid = 1;
const aid: (Aid & { sender: string; receiver: string; state: "out" | "done" })[] = [];
let nextAid = 1;
// Offers at the market, with the same states as the market_offers table (index.ts).
const offers: (Offer & { seller: string; state: string; buyer: string | null; buyer_name: string; sold_at: number | null })[] = [];
let nextOffer = 1;
const store = new MemoryAllianceStore(() => new Map([...players].map(([id, p]) => [id,
  { name: p.name, level: castleLevel(p.castle), might: might(p.castle, pvp) }])));
const chat = new MemoryChatStore();
// Who holds each village and capital; `holder` is the owner's account (null for the militia).
const villages = new Map<string, VillageState & { holder: string | null }>(
  PLACES.map((v) => [v.id, { ...untouched(v.id), holder: null }]));
// Alliance wars: the war points won, and up to when each capital's holder has had its hold points.
const warPoints: WarEntry[] = [];
const scoredAt = new Map<string, number>();
const warClaimed = new Map<string, number>();
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
      return { ...r, mine: own, army: own ? r.army : {}, waves: own ? r.waves : undefined, tools: own ? r.tools : undefined, lead: own ? r.lead : undefined, survivors: own ? r.survivors : {},
        loot: own ? r.loot : {} };
    });
  const helping = aid.filter((a) => (a.sender === user || a.receiver === user) && a.state === "out")
    .sort((a, b) => a.arrive - b.arrive).map(({ sender, receiver: _r, state: _s, ...a }) => ({ ...a, mine: sender === user }));
  return { ok: true, now: now(), ...extra, player: state, raids: moving, aid: helping, reports: mine,
    villages: villagesView(user), events: shifted(eventsView(eventRules, now() + EVENTS_OFFSET)) };
}

// --- Resource villages: the same as in index.ts, without the database ------------

function villagesView(user: string) {
  return PLACES.map((info) => {
    const v = villages.get(info.id)!;
    const { holder, ...state } = v;
    const vr = rulesFor(rules, info);
    return { id: info.id, owner: state.owner, mine: holder === user, tag: holder ? tagOf(holder) : "",
      ally: holder !== null && holder !== user && allies(user, holder), guard: state.guard, taken_at: state.taken_at,
      peace_until: vr.peaceUntil(state), stock: vr.stock(info, state, now()),
      ...(info.capital ? { buildings: state.buildings ?? {}, building: state.building ?? null } : {}) };
  });
}

/** How many villages (or, with `capital`, capitals) this player holds. */
function held(user: string, capital = false): number {
  return PLACES.filter((info) => Boolean(info.capital) === capital && villages.get(info.id)!.holder === user).length;
}

/** The capitals held by this player's alliance (by the player alone outside one): their levels and their guild halls' levels. */
function allianceCapitals(user: string): { levels: number[]; guilds: number[] } {
  const out = { levels: [] as number[], guilds: [] as number[] };
  for (const info of world.capitals ?? []) {
    const v = villages.get(info.id)!;
    if (v.holder === null || (v.holder !== user && !allies(user, v.holder))) continue;
    out.levels.push(info.level);
    const guild = rules.capitals.buildingLevel(v, "guildhall", now());
    if (guild > 0) out.guilds.push(guild);
  }
  return out;
}

function hasRoom(user: string, info: VillageInfo): boolean {
  const p = players.get(user);
  if (!p) return false;
  const vr = rulesFor(rules, info);
  if (vr.checkRoom(castleLevel(p.castle), held(user, Boolean(info.capital))) !== "") return false;
  return !(vr instanceof CapitalRules) || vr.checkAlliance(allianceCapitals(user).levels.length) === "";
}

function findVillage(id: unknown, user: string): { target: VillageTarget; holder: string | null } | undefined {
  const info = PLACES.find((v) => v.id === id);
  if (!info) return undefined;
  const { holder, ...state } = villages.get(info.id)!;
  const target: VillageTarget = { info, state, ally: holder !== null && holder !== user && allies(user, holder),
    held: held(user, Boolean(info.capital)) };
  if (info.capital) target.allianceHeld = allianceCapitals(user).levels.length;
  return { target, holder };
}

function collectVillages(user: string): Record<string, number> {
  const income: Record<string, number> = {};
  for (const info of PLACES) {
    const v = villages.get(info.id)!;
    if (v.holder !== user) continue;
    const paid = rulesFor(rules, info).collect(info, v, now());
    if (paid.amount <= 0) continue;
    v.paid_at = paid.paid_at;
    income[info.resource] = (income[info.resource] ?? 0) + paid.amount;
  }
  return income;
}

function sendHome(user: string, villageId: string, survivors: Record<string, number>, t: number) {
  const p = players.get(user);
  const info = PLACES.find((v) => v.id === villageId);
  if (!p || !info || Object.keys(survivors).length === 0) return;
  const travel = rules.barons.marchTime(Math.hypot(info.position[0] - p.home_x, info.position[1] - p.home_y));
  raids.push({ id: nextRaid++, attacker: user, defender: null, attacker_name: p.name, defender_name: info.name, village: info.id,
    mission: "return", army: {}, from: [p.home_x, p.home_y], to: info.position, depart: t, arrive: t, back: t + travel,
    state: "home", survivors, loot: {} });
}

function resolveVillageRaids() {
  for (const raid of raids.filter((r) => r.village && r.state === "out" && r.arrive <= now()).sort((a, b) => a.arrive - b.arrive)) {
    const info = PLACES.find((v) => v.id === raid.village)!;
    const v = villages.get(info.id)!;
    const { holder, ...before } = v;
    const room = hasRoom(raid.attacker, info);
    const out = resolveVillageRaid(rules, info, before, raid, room);
    const captured = out.state.owner !== before.owner;
    villages.set(info.id, { ...out.state, holder: captured ? raid.attacker : holder });
    if (info.capital && out.attackerReport?.result === "fought") {
      // The same as warPointsForBattle() in index.ts.
      const at = raid.arrive;
      if (captured) {
        const old = warAlliance(holder);
        if (old) warPoints.push(...holdEntries(warRules, info, old, Math.max(scoredAt.get(info.id) ?? 0, before.taken_at), at));
        scoredAt.set(info.id, Math.max(scoredAt.get(info.id) ?? 0, Math.floor(at)));
        const mine = warAlliance(raid.attacker);
        const already = mine !== null && warPoints.some((e) => e.kind === "capture" && e.alliance_id === mine.id &&
          e.capital === info.id && e.season === seasonAt(warRules, at).start);
        const entry = mine ? captureEntry(warRules, info, mine, at, already) : null;
        if (entry) warPoints.push(entry);
      } else if (holder && out.attackerReport.winner === "b") {
        const mine = warAlliance(holder);
        const entry = mine ? defenceEntry(warRules, info, mine, at, out.attackerReport.a ?? {}) : null;
        if (entry) warPoints.push(entry);
      }
    }
    if (out.attackerReport) report(raid.attacker, out.attackerReport);
    if (out.ownerReport && holder) report(holder, out.ownerReport);
    if (captured && holder) sendHome(holder, info.id, out.guardHome, raid.arrive);
    const stays = Object.keys(out.survivors).length === 0 && out.attackerReport?.result !== "fought";
    Object.assign(raid, stays ? { state: "done" }
      : { state: "home", survivors: out.survivors, loot: out.loot, ...(out.lead ? { lead: out.lead } : {}) });
  }
}

function villageOrder(user: string, body: Record<string, unknown>): string {
  const v = villages.get(String(body.village));
  if (!v) return "There's no such village.";
  if (v.holder !== user) return "That village isn't yours.";
  const abandon = body.action === "abandon_village";
  if (!abandon && Object.keys(v.guard).length === 0) return "No soldiers guard that village.";
  const guard = v.guard;
  // A capital's town buildings stay in the town; one still going up is lost.
  const buildings = settled(v, now()).buildings;
  const info = PLACES.find((p) => p.id === v.id)!;
  if (abandon && info.capital) {
    const mine = warAlliance(user);
    if (mine) warPoints.push(...holdEntries(warRules, info, mine, Math.max(scoredAt.get(v.id) ?? 0, v.taken_at), now()));
    scoredAt.set(v.id, Math.floor(now()));
  }
  if (abandon) villages.set(v.id, { ...untouched(v.id), ...(buildings ? { buildings } : {}), holder: null });
  else v.guard = {};
  sendHome(user, v.id, guard, now());
  return "";
}

// --- Alliance wars: the same as in index.ts, without the database ----------------

function warAlliance(user: string | null): WarAlliance | null {
  const m = user === null ? undefined : store.membership.get(user);
  const a = m === undefined ? undefined : store.alliancesById.get(m.alliance_id);
  return a === undefined ? null : { id: a.id, name: a.name, tag: a.tag };
}

function scoreCapitals() {
  for (const info of world.capitals ?? []) {
    const v = villages.get(info.id)!;
    const due = v.holder === null ? null : holdDue(scoredAt.get(info.id) ?? 0, v.taken_at, now());
    if (due === null) continue;
    scoredAt.set(info.id, due.to);
    const mine = warAlliance(v.holder);
    if (mine) warPoints.push(...holdEntries(warRules, info, mine, due.from, due.to));
  }
}

function warMember(user: string) {
  const m = store.membership.get(user);
  return { alliance_id: m?.alliance_id ?? null, joined: m?.joined ?? 0, war_claimed: warClaimed.get(user) ?? 0 };
}

function warView(user: string) {
  scoreCapitals();
  const t = now();
  const capitals = (world.capitals ?? []).map((info) => {
    const v = villages.get(info.id)!;
    const m = v.holder === null ? undefined : store.membership.get(v.holder);
    return { id: info.id, name: info.name, level: info.level, owner: v.owner, alliance_id: m?.alliance_id ?? null,
      tag: v.holder === null ? "" : tagOf(v.holder) };
  });
  return warBoard(warRules, t, standings(warPoints, seasonAt(warRules, t).start), standings(warPoints, lastSeason(warRules, t).start),
    capitals, players.has(user) ? warMember(user) : null);
}

function claimWarPrize(user: string): string {
  const t = now();
  const last = lastSeason(warRules, t);
  const me = warMember(user);
  const prize = checkClaim(warRules, me, standings(warPoints, last.start).find((s) => s.alliance_id === me.alliance_id), t);
  if (typeof prize === "string") return prize;
  const p = players.get(user)!;
  const castle = CastleState.fromDict(rules.buildings, p.castle);
  givePrize(castle, prize);
  players.set(user, { ...p, castle: castle.toDict() });
  warClaimed.set(user, last.start);
  return "";
}

/** Every player's season columns, as the database keeps them. */
function seasonRows() {
  return [...players.entries()].map(([id, p]) => ({ id, name: p.name, alliance_id: store.membership.get(id)?.alliance_id ?? null,
    ...seasonColumns(p.castle, seasonRules) }));
}

/** What a player earned in the season before this one: {key, points, claimed}, or null. */
function lastSeasonOf(p: PlayerState, t: number) {
  const s = p.castle.season;
  if (!s) return null;
  if (s.key >= 0 && s.key !== seasonKey(t)) return { key: s.key, points: renown(p.castle, seasonRules), claimed: false };
  return s.last && "key" in s.last ? s.last : null;
}

function seasonPlaces(user: string, key: number, points: number) {
  const rows = seasonRows();
  const mine = store.membership.get(user)?.alliance_id;
  const at = mine === undefined ? -1 : allianceStandings(rows, key).findIndex(([id]) => id === mine);
  return { player: placeIn(rows, key, points), alliance: at < 0 ? 0 : at + 1 };
}

/** The event view with times moved back from the shifted calendar to the real clock. */
/** The players with horde points in the Ember Horde run starting at `key` (on the real clock), most first. */
function hordeRanking(key: number) {
  return [...players.entries()].filter(([, p]) => p.horde_key === key && (p.horde_points ?? 0) > 0)
    .map(([id, p]) => ({ id, name: p.name, points: p.horde_points ?? 0, tag: tagOf(id) }))
    .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
}

function shifted(v: ReturnType<typeof eventsView>) {
  const back = (e: { start: number; end: number }) => ({ ...e, start: e.start - EVENTS_OFFSET, end: e.end - EVENTS_OFFSET });
  return { active: v.active.map(back), upcoming: v.upcoming.map(back), recent: v.recent.map(back) };
}

/** The same as adminOrder in index.ts, on the shifted calendar. */
function adminOrder(user: string, body: Record<string, unknown>) {
  if (!isAdmin(user)) {
    return body.action === "admin"
      ? { ok: true, now: now(), error: "", result: { admin: { is_admin: false } } }
      : { ok: true, now: now(), error: NOT_ADMIN };
  }
  const t = now() + EVENTS_OFFSET;
  let error = "";
  let details: Record<string, unknown> | null = null;
  if (body.action === "admin_start_event" || body.action === "admin_stop_event") {
    const o = body.action === "admin_start_event" ? startEvent(eventRules, body.event, body.hours, t) : stopEvent(eventRules, body.event, t);
    if (typeof o === "string") error = o;
    else {
      eventRules = withOverrides(eventRules0,
        [...(eventRules.overrides ?? []).filter((x: EventOverride) => x.event !== o.event || x.start !== o.start), o]);
      details = { event: o.event, start: o.start - EVENTS_OFFSET, end: o.end - EVENTS_OFFSET };
    }
  } else if (body.action === "admin_give") {
    const gift = checkGift(rules.buildings.resources, (u) => rules.buildings.hasUnit(u), body.resources, body.troops);
    const name = typeof body.target === "string" ? body.target.trim().toLowerCase() : "";
    const targets = [...players.entries()].filter(([, p]) => body.target === "*" || p.name.toLowerCase() === name);
    if (typeof gift === "string") error = gift;
    else if (targets.length === 0) error = body.target === "*" ? "There are no players yet." : "There's no player by that name.";
    else {
      for (const [id, p] of targets) {
        const castle = CastleState.fromDict(rules.buildings, p.castle);
        giveCastle(castle, gift);
        players.set(id, { ...p, castle: castle.toDict() });
        report(id, giftReport(gift, now()));
      }
      details = { target: body.target === "*" ? "everyone" : targets[0][1].name, castles: targets.length, ...gift };
    }
  } else if (body.action !== "admin") error = "Unknown order.";
  if (details !== null) adminLog.unshift({ at: now(), action: String(body.action), details });
  const events = adminEvents(eventRules, now() + EVENTS_OFFSET)
    .map((e) => e.on ? { ...e, start: e.start - EVENTS_OFFSET, end: e.end - EVENTS_OFFSET } : e);
  return { ok: true, now: now(), error, result: { admin: { is_admin: true, events,
    players: [...players.values()].map((p) => p.name).sort(), log: adminLog.slice(0, 20) } } };
}

function report(user: string, r: { at: number }) {
  reports.push({ id: nextReport++, user, at: r.at, report: r });
}

// --- The market: the same as in index.ts, without the database -------------------

const offerOf = ({ seller: _s, state: _st, buyer: _b, buyer_name: _bn, sold_at: _sa, ...o }: (typeof offers)[number]): Offer => o;

function marketView(user: string) {
  const t = now();
  const mine = offers.filter((o) => o.seller === user).reverse();
  return {
    offers: offers.filter((o) => o.state === "open" && o.expires > t && o.seller !== user).reverse().slice(0, 200)
      .map((o) => ({ ...offerOf(o), tag: tagOf(o.seller) })),
    mine: mine.filter((o) => o.state === "open" && o.expires > t).map(offerOf),
    sold: mine.filter((o) => o.state === "sold" || o.state === "paid").slice(0, 10)
      .map((o) => ({ ...offerOf(o), buyer_name: o.buyer_name, sold_at: o.sold_at })),
    rates: goingRates(offers.filter((o) => o.sold_at !== null).sort((a, b) => b.sold_at! - a.sold_at!).slice(0, 200)),
  };
}

function collectMarket(user: string): { income: Record<string, number>; reports: MarketReport[] } {
  const income: Record<string, number> = {};
  const out: MarketReport[] = [];
  for (const o of offers.filter((x) => x.seller === user)) {
    if (o.state === "sold") {
      o.state = "paid";
      income[o.want] = (income[o.want] ?? 0) + o.proceeds;
    } else if (o.state === "cancelled" || (o.state === "open" && o.expires <= now())) {
      if (o.state === "open") out.push({ kind: "market", event: "expired", at: o.expires, give: o.give, give_amount: o.give_amount,
        want: o.want, want_amount: o.want_amount });
      o.state = "returned";
      income[o.give] = (income[o.give] ?? 0) + o.give_amount;
    }
  }
  return { income, reports: out };
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
  for (const raid of raids.filter((r) => !r.village && r.state === "out" && r.arrive <= now() && (r.attacker === user || r.defender === user))
    .sort((a, b) => a.arrive - b.arrive)) {
    const defender = players.get(raid.defender!);
    if (defender === undefined) continue;
    const helpers = helpersAt(raid.defender!, raid.arrive);
    const outcome = fightRaid(rules, pvp, defender, raid, helpers.map((h) => h.army));
    players.set(raid.defender!, outcome.defender);
    for (const r of outcome.campReports) report(raid.defender!, r);
    if (helpers.length > 0) outcome.defenderReport.helped_by = [...new Set(helpers.map((h) => h.sender_name))];
    report(raid.defender!, outcome.defenderReport);
    report(raid.attacker, outcome.attackerReport);
    Object.assign(raid, { state: "home", survivors: outcome.survivors, loot: outcome.loot, won: outcome.attackerReport.winner === "a",
      ...(outcome.lead ? { lead: outcome.lead } : {}) });
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
      return { target: { name: p.name, home: [p.home_x, p.home_y], protected: isProtected(p, pvp, now()),
        level: castleLevel(p.castle), ally: allies(me, id) },
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
    if (typeof body.action === "string" && body.action.startsWith("admin")) return send(res, 200, adminOrder(user, body));
    const takenSpots = () => [...players.values()].flatMap((p) =>
      [[p.home_x, p.home_y] as [number, number], ...(p.outpost ? [[p.outpost.x, p.outpost.y] as [number, number]] : [])]);
    if (body.action === "join") {
      const why = checkName(body.name);
      if (why !== "") return send(res, 200, { ok: false, error: why });
      if (players.has(user)) return send(res, 200, { ok: false, error: "You already have a castle." });
      const taken = [...players.values()].some((p) => p.name.toLowerCase() === String(body.name).trim().toLowerCase());
      if (taken) return send(res, 200, { ok: false, error: "That name is taken." });
      const spot = pickSpot(world, takenSpots());
      if (spot === null) return send(res, 200, { ok: false, error: "The world is full. Try again later." });
      const state = newPlayer(rules, world, String(body.name), now(), spot, pvp);
      state.castle.troops = { ...START_TROOPS };
      Object.assign(state.castle.resources, START_RESOURCES);
      const keep = state.castle.buildings.find((b) => b.type === "keep");
      if (keep && START_KEEP > 0) keep.level = START_KEEP;
      const placed = hordeArrives(invade(state, eventRules, world, now(), EVENTS_OFFSET), eventRules, world, now(), EVENTS_OFFSET);
      players.set(user, placed);
      return send(res, 200, view(user, placed));
    }
    if (body.action === "world") {
      const others = [...players.entries()].filter(([id]) => id !== user)
        .map(([id, p]) => ({ name: p.name, home_x: p.home_x, home_y: p.home_y, level: castleLevel(p.castle),
          protected: isProtected(p, pvp, now()), tag: tagOf(id), title: p.castle.achievements?.title ?? "", ally: allies(user, id),
          outpost: p.outpost ? { name: p.outpost.name, x: p.outpost.x, y: p.outpost.y } : null }));
      return send(res, 200, { ok: true, now: now(), error: "", players: others });
    }
    if (body.action === "leaderboard") {
      const all = [...players.entries()].map(([id, p]) => ({ id, name: p.name, level: castleLevel(p.castle),
        might: might(p.castle, pvp), barons_beaten: p.barons_beaten ?? 0, tag: tagOf(id), title: p.castle.achievements?.title ?? "" }))
        .sort((a, b) => b.might - a.might || b.barons_beaten - a.barons_beaten || a.name.localeCompare(b.name));
      const strip = ({ id: _id, ...row }: (typeof all)[number]) => row;
      const mine = all.find((r) => r.id === user);
      const rank = mine ? all.filter((r) => r.might > mine.might).length + 1 : 0;
      return send(res, 200, { ok: true, now: now(), error: "",
        result: { players: all.slice(0, 50).map(strip), me: mine ? strip(mine) : null, rank, total: all.length } });
    }
    if (body.action === "season_board") {
      const t = now();
      const key = seasonKey(t);
      const rows = seasonRows();
      const players_ = rows.filter((r) => r.season_key === key && r.season_points > 0)
        .sort((a, b) => b.season_points - a.season_points || a.name.localeCompare(b.name)).slice(0, 50)
        .map((r) => ({ name: r.name, points: r.season_points, tag: tagOf(r.id) }));
      const alliances = allianceStandings(rows, key).slice(0, 5).map(([id, points]) => {
        const a = store.alliancesById.get(id);
        return { tag: a?.tag ?? "", name: a?.name ?? "", points };
      });
      const p = players.get(user)!;
      const points = p.castle.season?.key === key ? renown(p.castle, seasonRules) : 0;
      const prev = lastSeasonOf(p, t);
      const places = prev ? seasonPlaces(user, prev.key, prev.points) : null;
      return send(res, 200, { ok: true, now: t, error: "", result: { key, end: seasonEnd(key), players: players_, alliances,
        me: { points, place: points > 0 ? placeIn(rows, key, points) : 0 },
        last: prev && places ? { key: prev.key, points: prev.points, place: places.player, alliance_place: places.alliance, claimed: prev.claimed } : {} } });
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
        event: inv === undefined ? null : shifted({ active: [inv], upcoming: [], recent: [] }).active[0],
        players: all.slice(0, 50).map(strip), me: mine ? strip(mine) : null, rank, total: all.length } });
    }
    if (body.action === "horde_board") {
      const run = lastHorde(eventRules, now() + EVENTS_OFFSET);
      const key = run === undefined ? -1 : run.start - EVENTS_OFFSET;
      const all = hordeRanking(key);
      const strip = ({ id: _id, ...row }: (typeof all)[number]) => row;
      const mine = all.find((r) => r.id === user);
      const rank = mine ? all.filter((r) => r.points > mine.points).length + 1 : 0;
      return send(res, 200, { ok: true, now: now(), error: "", result: {
        event: run === undefined ? null : shifted({ active: [run], upcoming: [], recent: [] }).active[0],
        players: all.slice(0, 50).map(strip), me: mine ? strip(mine) : null, rank, total: all.length,
        prize: mine && run?.horde ? prizeFor(run.horde.prizes, rank) ?? null : null } });
    }
    if (body.action === "war_board") return send(res, 200, { ok: true, now: now(), error: "", result: { war: warView(user) } });
    if (!players.has(user)) return send(res, 200, { ok: false, error: "No castle yet.", needs_join: true });
    if (body.action === "chat" || body.action === "chat_send") {
      const error = body.action === "chat_send" ? await sendChat(chat, speaker(user), body, now()) : "";
      return send(res, 200, { ok: true, now: now(), error, result: await chatView(chat, speaker(user), body.after) });
    }
    if (body.action === "market") return send(res, 200, { ok: true, now: now(), error: "", result: marketView(user) });
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
    // The same as the market orders in index.ts.
    const marketOrder = ["post_offer", "buy_offer", "cancel_offer"].includes(String(body.action));
    let marketError = "";
    if (body.action === "cancel_offer") {
      const o = offers.find((x) => x.id === Number(body.id) && x.seller === user && x.state === "open");
      if (o) o.state = "cancelled";
      else marketError = "That offer is gone.";
      body.action = "state";
    }
    let bought: (typeof offers)[number] | undefined;
    if (body.action === "buy_offer") {
      bought = offers.find((x) => x.id === Number(body.id) && x.state === "open" && x.expires > now());
      if (bought?.seller === user) marketError = "That's your own offer.";
      else if (bought === undefined) marketError = "That offer is gone.";
      if (marketError !== "") {
        bought = undefined;
        body.action = "state";
      }
    }
    resolveAid(user);
    resolveRaids(user);
    resolveVillageRaids();
    scoreCapitals();
    let warError = "";
    if (body.action === "claim_war_prize") {
      warError = claimWarPrize(user);
      body.action = "state";
    }
    const villageIncome = collectVillages(user);
    const market = collectMarket(user);
    let villageError = "";
    if (body.action === "recall_guard" || body.action === "abandon_village") {
      villageError = villageOrder(user, body);
      body.action = "state";
    }
    const village = ["attack_village", "station", "build_capital"].includes(String(body.action)) ? findVillage(body.village, user) : undefined;
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
    const me = players.get(user)!;
    const outpostSpot = body.action === "found_outpost" && !me.outpost ? nearestSpot(world.spots, [me.home_x, me.home_y], takenSpots()) : null;
    let hordePlace = 0;
    if (body.action === "claim_horde_prize" && (me.horde_points ?? 0) > 0) {
      hordePlace = hordeRanking(me.horde_key ?? 0).filter((r) => r.points > (me.horde_points ?? 0)).length + 1;
    }
    let seasonPlace: { player: number; alliance: number } | undefined;
    if (body.action === "claim_season_prize") {
      const prev = lastSeasonOf(me, t);
      seasonPlace = prev && prev.points > 0 ? seasonPlaces(user, prev.key, prev.points) : { player: 0, alliance: 0 };
    }
    const outcome = act(rules, me, body, t,
      { pvp, outpostSpot, target: target?.target, homecomings, alliances: allianceRules, aid: aidRules,
        events: { rules: eventRules, world, offset: EVENTS_OFFSET }, quests: questRules, achievements: achievementRules, login: loginRules, seasons: seasonRules, seasonPlace, chests: chestRules, village: village?.target, villageIncome,
        capitalBoost: capitalBoost(rules, allianceCapitals(user).levels, allianceCapitals(user).guilds), fortresses: world.fortresses, hordeRank: hordePlace,
        market: { rules: marketRules, open: offers.filter((o) => o.seller === user && o.state === "open" && o.expires > t).length,
          offer: bought ? offerOf(bought) : undefined }, marketIncome: market.income });
    players.set(user, outcome.state);
    for (const r of [...outcome.reports, ...market.reports, ...(outcome.marketReports ?? [])]) report(user, r);
    if (outcome.offer) offers.push({ ...outcome.offer, id: nextOffer++, seller: user, state: "open", buyer: null, buyer_name: "", sold_at: null });
    if (bought && outcome.error === "") {
      Object.assign(bought, { state: "sold", buyer: user, buyer_name: outcome.state.name, sold_at: t });
      report(bought.seller, { kind: "market", event: "sold", at: t, name: outcome.state.name, give: bought.give,
        give_amount: bought.give_amount, want: bought.want, want_amount: bought.want_amount, proceeds: bought.proceeds } as MarketReport);
    }
    if (outcome.capitalBuild && village) villages.set(village.target.info.id, { ...outcome.capitalBuild.state, holder: user });
    if (outcome.raid && village) {
      raids.push({ ...outcome.raid, id: nextRaid++, attacker: user, defender: outcome.raid.mission === "attack" ? village.holder : null });
    } else if (outcome.raid && target) raids.push({ ...outcome.raid, id: nextRaid++, attacker: user, defender: target.user });
    if (outcome.aid && target) aid.push({ ...outcome.aid, id: nextAid++, sender: user, receiver: target.user, state: "out" });
    let result = outcome.result ?? null;
    if (body.action === "spy" && outcome.error === "" && target) {
      result = spyReport(rules, pvp, players.get(target.user)!, t, helpersAt(target.user, t).map((h) => h.army));
    }
    if (founded !== null) {
      if (outcome.error !== "") await store.remove(founded);
      result = await allianceView(store, allianceRules, user);
    }
    if (marketOrder) result = marketView(user);
    return send(res, 200, view(user, outcome.state, { error: recalled || villageError || marketError || warError || outcome.error, result }));
  }
  send(res, 404, { msg: "Not found" });
}).listen(PORT, "127.0.0.1", () => console.log(`Local game server on http://127.0.0.1:${PORT}`));
