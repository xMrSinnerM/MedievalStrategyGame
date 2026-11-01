// The game server: one Edge Function that every online order goes through.
// The caller must be signed in (Supabase Auth). It loads their player row,
// runs their world up to the server's clock, carries out the order and saves
// the result, so the game never decides anything itself.
//
// POST { "action": "join", "name": "..." }       create your castle on a free spot
// POST { "action": "state" }                     your castle, camps, marches, raids and reports
// POST { "action": "world" }                     other players: name, spot, level, protection
// POST { "action": "leaderboard" }               the mightiest castles, and your own rank
// POST { "action": "event_board" }               the most event points in the Baron Invasion, and your rank
// POST { "action": "claim_reward", "tier": n }   the invasion's next reward tier (data/events.json)
// POST { "action": "horde_board" }               the most horde points in the Ember Horde, your rank and your prize
// POST { "action": "buy_horde", "item": id }      something from the Trophy Market, for war trophies (data/events.json)
// POST { "action": "claim_horde_prize" }          your ranked prize, once the Ember Horde has gone
// POST { "action": "war_board" }                 the alliance war: this season's and the last season's standings, the capitals
//   and who holds them, your alliance's place and the prize you can claim (data/wars.json)
// POST { "action": "claim_war_prize" }           your prize for your alliance's place in the last war season
// POST { "action": "tournament" }               this week's alliance tournament: the bracket with its scores, your alliance's
//   run and the prize you can claim from the last finished one (data/tournaments.json)
// POST { "action": "claim_tournament_prize" }    your prize for how far your alliance got in the last finished tournament
// POST { "action": "claim_quest", "kind": "story" | "daily" | "chest", "index": n }   a quest reward (data/quests.json)
// POST { "action": "open_chest", "kind": "wooden" | "iron" | "golden" }   spins a treasure chest's wheel (data/chests.json)
// POST { "action": "encounter", "id": id, "choice": "quarter" | "half" | "all" }   a bandit camp, caravan or treasure site on the map (data/encounters.json)
// POST { "action": "claim_season" }               the next reward on this season's renown track (data/seasons.json)
// POST { "action": "claim_season_prize" }         last season's prizes for your place and your alliance's
// POST { "action": "season_board" }               this season's best players and alliances, and your places
// POST { "action": "claim_login" }                today's Royal Gift for coming back (data/login.json)
// POST { "action": "claim_achievement", "id": id }  an achievement's next earned reward (data/achievements.json)
// POST { "action": "set_title", "title": "id:tier" | "" }   the title shown with your name
// POST { "action": "place", "type", "cell": [x, y] }
// POST { "action": "upgrade" | "cancel", "id" }
// POST { "action": "move", "id", "cell": [x, y] }
// POST { "action": "recruit", "unit", "amount" }
// POST { "action": "cancel_training", "index" }
// POST { "action": "craft", "tool", "amount" }    siege tools from the workshop (data/units.json "tools")
// POST { "action": "cancel_crafting", "index" }
// POST { "action": "research", "study" }         the next level of a study in your academy (data/buildings.json "research")
// POST { "action": "cancel_research" }
// POST { "action": "set_tools", "tools": { "left" | "front" | "right": { tool: count } } }   defence tools on your walls
// POST { "action": "attack", "camp", "army": { unit: count } }
// POST { "action": "attack_player", "target": "name", "army": { unit: count } }
//   "attack" and "attack_player" also take "waves": [{ "left" | "front" | "right": { unit: count } }, ...]
//   instead of "army": how the army storms the walls (up to wavesForKeep() waves, server/rules/battle.ts),
//   and "tools": { "left" | "front" | "right": { tool: count } }, attack tools from your store,
//   and "commander": id, the commander to lead the army (data/gear.json)
// POST { "action": "equip", "who": commander id | "castellan", "item": id }   gear from your bag
// POST { "action": "unequip", "who": commander id | "castellan", "slot": "helmet" | "armour" | "weapon" | "banner" }
// POST { "action": "sell_gear", "item": id }     sells gear from your bag for gold
// POST { "action": "melt_gear", "item": id }     melts gear from your bag down for Marks
// POST { "action": "socket_gem", "item": id, "gem": "ruby:2" }   sets a gem from your pouch into gear in your bag
// POST { "action": "unsocket_gem", "item": id, "index": n }      prises a gem back out, for Marks
// POST { "action": "fuse_gems", "gem": "ruby:2" } fuses three of a gem into one of the next tier
// POST { "action": "forge_gear", "items": [id, id, id] }        three pieces of one rarity into one of the next (data/gear.json)
// POST { "action": "set_layout", "layout": { "left", "front", "right", "courtyard" } }   percent of the garrison at each post
// POST { "action": "spy", "target": "name" }
// POST { "action": "sabotage_player", "target": "name", "mission": "steal" | "burn_stores" | "burn_walls", "resource": "wood", "agents": n }
// POST { "action": "sabotage_camp", "camp": id, "mission": "steal" | "burn_walls", "agents": n }   spies and sabotage (data/sabotage.json)
// POST { "action": "view_castle", "target": "name", "outpost": false }   another player's buildings, to look around inside
// POST { "action": "found_outpost", "region": "wood" | "stone" | "food" | "gold" }   a second castle (data/outposts.json)
//   on the free spot nearest your home; "place", "upgrade", "cancel" and "move" then take "castle": "outpost"
// POST { "action": "send_carts", "from": "home" | "outpost", "resources": { wood: n } }   between your castles
// POST { "action": "attack_village", "village": id, "army" | "waves", "tools", "commander" }   take a resource village (data/villages.json)
//   or a capital, by its town id (data/capitals.json)
// POST { "action": "station", "village": id, "army": { unit: count } }   soldiers to guard your village
// POST { "action": "recall_guard" | "abandon_village", "village": id }   bring your guards home (and give the village up)
// POST { "action": "build_capital", "village": id, "building": id }   the next level of a town building in your capital
//   (data/capitals.json "buildings"), paid from your castle
// POST { "action": "found_alliance", "name", "tag" }  costs gold (data/alliances.json)
// POST { "action": "alliance" }                  your alliance, its members and requests, invitations, all alliances
// POST { "action": "join_alliance" | "accept_invite" | "decline_invite" | "cancel_request", "id" }
// POST { "action": "leave_alliance" | "disband_alliance" }
// POST { "action": "invite" | "cancel_invite" | "kick", "target": "name" }
// POST { "action": "answer_request", "target": "name", "accept": true }
// POST { "action": "set_role", "target": "name", "role": "leader" | "officer" | "member" }
// POST { "action": "alliance_settings", "open": true, "description": "..." }
// POST { "action": "chat", "after": id }         world and alliance messages newer than `after`
// POST { "action": "chat_send", "channel": "world" | "alliance", "text": "...", "after": id }
// POST { "action": "mail", "folder": "inbox" | "sent" | "reports", "before": id }   a page of your letters or reports
//   (mail.ts), newest first, and how many are unread; every answer with your castle also carries `mail_unread`
// POST { "action": "mail_send", "to": "name" | "alliance": true, "subject": "...", "text": "...", "folder" }
// POST { "action": "mail_read" | "mail_delete", "folder", "ids": [id, ...] }   (mail_read_all: the whole folder)
// POST { "action": "send_resources", "target": "name", "resources": { wood: n } }   to an ally (data/aid.json)
// POST { "action": "send_defenders", "target": "name", "army": { unit: count } }
// POST { "action": "recall_defenders", "id" }
// POST { "action": "market" }                    open offers at the market, yours, and the going rates (data/market.json)
// POST { "action": "post_offer", "give": "wood", "give_amount": n, "want": "stone", "want_amount": n }
// POST { "action": "buy_offer" | "cancel_offer", "id" }
// POST { "action": "admin" }                     the owner's panel: events, player names, admin log (owner only)
// POST { "action": "admin_start_event" | "admin_stop_event", "event": "id", "hours": n }   (owner only)
// POST { "action": "admin_give", "target": "name" | "*", "resources": { wood: n }, "troops": { unit: n } }   (owner only)
//
// Armies sent against players are rows in the raids table. Whenever either
// side sends a request after an army has arrived, the battle is fought on
// the defender's castle as it was at that moment; survivors and loot reach
// the attacker's castle with their first request after the army is back.
// Alliance orders answer with the alliance screen's view (alliances.ts).
// Help for allies is a row in the aid table (aid.ts): carts unload into the
// ally's castle with the first request after they arrive, and defenders
// standing in a castle fight beside its garrison when an attack is resolved.
// Every answer with your castle also lists the timed events on now and next
// (data/events.json); they change battles as they are resolved.
// Resource villages are rows of the villages table, shared by everyone
// (villages.ts). Armies sent to them are raids rows with `village` set,
// resolved by the first request after they arrive, whoever sends it; every
// request first collects what your villages made, and every answer with your
// castle lists who holds each village.
// Capitals (the towns) are rows of the same table, with their own rules
// (data/capitals.json); every request sets your castle's production boost
// from the capitals your alliance holds (or you alone, outside one) and
// their guild halls. A capital's town buildings are columns of its row.
// Alliance wars (wars.ts): alliances win war points with the capitals in
// weekly seasons, as rows of war_points. Every request first gives each
// capital's holder's alliance its hold points up to the start of the hour
// (villages.scored_at is up to when), and a battle at a capital adds points
// for taking it or holding it.
// Market offers are rows of the market_offers table (market.ts): a buyer
// takes an offer before paying for it, and every request first brings the
// proceeds of your sales and the goods of your cancelled or expired offers
// home. Market orders answer with the market's view as `result`.
// Fortresses (the old kingdoms' castles) are every player's own camps, like
// the robber barons' (data/fortresses.json); act() adds them to a player who
// doesn't have them yet.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import buildings from "../../../data/buildings.json" with { type: "json" };
import units from "../../../data/units.json" with { type: "json" };
import barons from "../../../data/barons.json" with { type: "json" };
import pvpData from "../../../data/pvp.json" with { type: "json" };
import alliancesData from "../../../data/alliances.json" with { type: "json" };
import aidData from "../../../data/aid.json" with { type: "json" };
import marketData from "../../../data/market.json" with { type: "json" };
import eventsData from "../../../data/events.json" with { type: "json" };
import questsData from "../../../data/quests.json" with { type: "json" };
import achievementsData from "../../../data/achievements.json" with { type: "json" };
import loginData from "../../../data/login.json" with { type: "json" };
import seasonsData from "../../../data/seasons.json" with { type: "json" };
import chestsData from "../../../data/chests.json" with { type: "json" };
import encountersData from "../../../data/encounters.json" with { type: "json" };
import weatherData from "../../../data/weather.json" with { type: "json" };
import sabotageData from "../../../data/sabotage.json" with { type: "json" };
import roadsData from "../../../data/roads.json" with { type: "json" };
import gearData from "../../../data/gear.json" with { type: "json" };
import outpostsData from "../../../data/outposts.json" with { type: "json" };
import villagesData from "../../../data/villages.json" with { type: "json" };
import capitalsData from "../../../data/capitals.json" with { type: "json" };
import fortressesData from "../../../data/fortresses.json" with { type: "json" };
import hordeData from "../../../data/horde.json" with { type: "json" };
import warsData from "../../../data/wars.json" with { type: "json" };
import tournamentsData from "../../../data/tournaments.json" with { type: "json" };
import world from "../../../server/world/world.json" with { type: "json" };
import { makeRules } from "../../../server/rules/load.ts";
import { effectAt, eventsView, lastHorde, lastInvasion, withOverrides, type EventOverride, type EventRules } from "../../../server/rules/events.ts";
import { CastleState } from "../../../server/rules/castle_state.ts";
import type { Item } from "../../../server/rules/gear.ts";
import { nearestSpot } from "../../../server/rules/outposts.ts";
import { CapitalRules, rulesFor, settled, type VillageInfo, type VillageState } from "../../../server/rules/villages.ts";
import { capitalBoost, resolveVillageRaid, type VillageTarget } from "./villages.ts";
import {
  act, castleLevel, castleView, checkName, fightRaid, isProtected, might, newPlayer, pickSpot, sabotagePlayer, spyReport,
  type Homecoming, type PlayerState, type PvpRules, type Raid, type Target, type World,
} from "./game.ts";
import { allianceView, checkFound, found, handle, type AllianceRules } from "./alliances.ts";
import { DatabaseAllianceStore } from "./alliance_store.ts";
import { chatView, send, type Speaker } from "./chat.ts";
import { DatabaseChatStore } from "./chat_store.ts";
import { type Directory, MAIL_ORDERS, mailOrder, mailView, sendLetter } from "./mail.ts";
import { DatabaseMailStore } from "./mail_store.ts";
import { deliver, recall, type Aid, type AidRules } from "./aid.ts";
import { goingRates, isItemGood, MARKS, receiveItem, type MarketReport, type MarketRules, type Offer } from "./market.ts";
import { invade } from "./invasion.ts";
import { hordeArrives, prizeFor } from "./horde.ts";
import {
  captureEntry, checkClaim, defenceEntry, givePrize, holdDue, holdEntries, hourStart, lastSeason, ranked, seasonAt, warBoard,
  type CapitalHold, type Standing, type WarAlliance, type WarEntry, type WarRules,
} from "./wars.ts";
import {
  bracket, checkClaim as checkTourneyClaim, claimableWeek, draw, roundScores, tourneyBoard, tourneyColumns, weekAt,
  type Entrant, type Round, type TourneyMember, type TourneyRow, type TourneyRules,
} from "./tournaments.ts";
import type { QuestRules } from "../../../server/rules/quests.ts";
import type { AchievementRules } from "../../../server/rules/achievements.ts";
import type { LoginRules } from "../../../server/rules/login.ts";
import type { ChestRules } from "../../../server/rules/chests.ts";
import { encounterRules } from "../../../server/rules/encounters.ts";
import type { WeatherRules } from "../../../server/rules/weather.ts";
import type { SabotageRules } from "../../../server/rules/sabotage.ts";
import { allianceStandings, placeIn, renown, seasonColumns, seasonEnd, seasonKey, type SeasonRules } from "../../../server/rules/seasons.ts";
import {
  adminEvents, checkGift, giftReport, giveCastle, NOT_ADMIN, OVERRIDES_KEPT, startEvent, stopEvent, type Gift,
} from "./admin.ts";

const rules = makeRules(buildings, units, barons, gearData, outpostsData, villagesData, capitalsData, fortressesData, hordeData);
const CAPITALS: VillageInfo[] = (world as World).capitals ?? [];
const VILLAGES: VillageInfo[] = [...((world as World).villages ?? []), ...CAPITALS];
const CAPITAL_IDS = CAPITALS.map((c) => c.id);
const VILLAGE_COLUMNS = "id, owner, owner_name, guard, taken_at, paid_at, buildings, building, scored_at, version";
const pvp = pvpData as PvpRules;
const allianceRules = alliancesData as AllianceRules;
const aidRules = aidData as AidRules;
const marketRules = marketData as unknown as MarketRules;
const eventRules = eventsData as EventRules;
const questRules = questsData as unknown as QuestRules;
const warRules = warsData as WarRules;
const tourneyRules = tournamentsData as unknown as TourneyRules;
// Up to when this server has given out the capitals' hold points (scoreCapitals()).
let scoredUntil = 0;
const achievementRules = achievementsData as unknown as AchievementRules;
const loginRules = loginData as unknown as LoginRules;
const seasonRules = seasonsData as unknown as SeasonRules;
const chestRules = chestsData as unknown as ChestRules;
const encounters = encounterRules(encountersData, roadsData);
const weather = weatherData as unknown as WeatherRules;
const sabotageRules = sabotageData as unknown as SabotageRules;
// The calendar with the game owner's changes (admin.ts), loaded with every request.
let calendar: EventRules = eventRules;
rules.barons.lootFactor = (t) => effectAt(calendar, t, "baron_loot");
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const store = new DatabaseAllianceStore(admin);
const chat = new DatabaseChatStore(admin);
const mail = new DatabaseMailStore(admin);
const directory: Directory = {
  byName: async (name) => {
    const p = await store.playerByName(name);
    return p === null ? null : { user: p.user, name: p.name };
  },
  members: async (id) => (await store.members(id)).map((m) => ({ user: m.user, name: m.name })),
};
const ALLIANCE_ORDERS = new Set([
  "alliance", "join_alliance", "accept_invite", "decline_invite", "cancel_request", "leave_alliance", "disband_alliance",
  "invite", "cancel_invite", "kick", "answer_request", "set_role", "alliance_settings",
]);
const COLUMNS = "name, home_x, home_y, castle, camps, marches, next_march, protected_until, barons_beaten, event_key, event_points, event_claimed, horde_key, horde_points, horde, outpost, version";
const REPORTS_SHOWN = 20;
const RETRIES = 4;
const PLAYERS_SHOWN = 500;
const RANKS_SHOWN = 50;
const OFFERS_SHOWN = 200;
/** Seconds after which a purchase still being paid for counts as failed. */
const STALE_PURCHASE = 120;
const SALES_COUNTED = 200;
const MARKET_ORDERS = new Set(["market", "post_offer", "buy_offer", "cancel_offer"]);

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

/** The browser build calls the server from another site, so every answer allows that (CORS). */
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function now(): number {
  return Date.now() / 1000;
}

function raidFromRow(r: Row): Raid {
  return {
    id: Number(r.id), attacker_name: r.attacker_name, defender_name: r.defender_name, army: r.army,
    ...(r.waves ? { waves: r.waves } : {}), ...(r.tools ? { tools: r.tools } : {}), ...(r.lead ? { lead: r.lead } : {}), from: [r.from_x, r.from_y], to: [r.to_x, r.to_y], depart: r.depart, arrive: r.arrive, back: r.back,
    state: r.state, survivors: r.survivors, loot: r.loot, ...(r.won ? { won: true } : {}), ...(r.village ? { village: r.village, mission: r.mission } : {}),
  };
}

function aidFromRow(r: Row): Aid {
  return {
    id: Number(r.id), kind: r.kind, sender_name: r.sender_name, receiver_name: r.receiver_name, resources: r.resources,
    army: r.army, from: [r.from_x, r.from_y], to: [r.to_x, r.to_y], depart: r.depart, arrive: r.arrive, leave: r.leave,
    back: r.back,
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
    return { ...raid, mine, army: mine ? raid.army : {}, waves: mine ? raid.waves : undefined,
      tools: mine ? raid.tools : undefined, lead: mine ? raid.lead : undefined, survivors: mine ? raid.survivors : {}, loot: mine ? raid.loot : {} };
  });
}

/** Carts and defenders you sent to allies, and theirs sent to you, until they are home. */
async function activeAid(userId: string) {
  const { data } = await admin.from("aid").select("*").or(`sender.eq.${userId},receiver.eq.${userId}`)
    .in("state", ["out", "delivering"]).order("arrive");
  return (data ?? []).map((r: Row) => ({ ...aidFromRow(r), mine: r.sender === userId }));
}

async function view(userId: string, state: PlayerState, extra: Record<string, unknown> = {}) {
  const [reports, raids, aid, villages, mail_unread] = await Promise.all([recentReports(userId), activeRaids(userId),
    activeAid(userId), villagesView(userId), mail.unread(userId)]);
  return { ok: true, now: now(), ...extra, player: state, raids, aid, reports, villages, mail_unread,
    events: eventsView(calendar, now()) };
}

// --- Resource villages (villages.ts) ------------------------------------------

let villagesReady = false;

/** Makes sure every village and capital on the map has its row (the militia hold new ones). */
async function ensureVillages() {
  if (villagesReady) return;
  const { error } = await admin.from("villages").upsert(VILLAGES.map((v) => ({ id: v.id })), { onConflict: "id", ignoreDuplicates: true });
  if (!error) villagesReady = true;
}

function villageInfo(id: unknown): VillageInfo | undefined {
  return VILLAGES.find((v) => v.id === id);
}

/** A villages row as the rules see it: a deleted owner leaves it to the militia. */
function villageState(r: Row): VillageState {
  return { id: r.id, owner: r.owner ? String(r.owner_name ?? "") : "", guard: r.guard ?? {}, taken_at: Number(r.taken_at),
    paid_at: Number(r.paid_at), buildings: r.buildings ?? {}, building: r.building ?? null };
}

/** Who holds each village, for the map: owner, alliance tag, guard, peace and what it holds now. */
async function villagesView(userId: string) {
  await ensureVillages();
  const { data } = await admin.from("villages")
    .select(`${VILLAGE_COLUMNS}, holder:players!villages_owner_fkey(alliance_id, alliance:alliances!players_alliance_id_fkey(tag))`);
  const me = await store.player(userId);
  const t = now();
  return (data ?? []).flatMap((r: Row) => {
    const info = villageInfo(r.id);
    if (!info) return [];
    const state = villageState(r);
    return [{
      id: r.id, owner: state.owner, mine: r.owner === userId, tag: r.holder?.alliance?.tag ?? "",
      ally: r.owner !== null && r.owner !== userId && me !== null && me.alliance_id !== null && Number(r.holder?.alliance_id) === me.alliance_id,
      guard: state.guard, taken_at: state.taken_at, peace_until: rulesFor(rules, info).peaceUntil(state),
      stock: rulesFor(rules, info).stock(info, state, t),
      ...(info.capital ? { buildings: state.buildings, building: state.building } : {}),
    }];
  });
}

/** How many villages, and how many capitals, this player holds. */
async function holdings(userId: string): Promise<{ villages: number; capitals: number }> {
  const { data } = await admin.from("villages").select("id").eq("owner", userId);
  const capitals = (data ?? []).filter((r: Row) => CAPITAL_IDS.includes(r.id)).length;
  return { villages: (data ?? []).length - capitals, capitals };
}

/** The capitals held by this player's alliance (by the player alone outside one): their levels and their guild halls' levels. */
async function allianceCapitals(userId: string): Promise<{ levels: number[]; guilds: number[] }> {
  const me = await store.player(userId);
  const { data } = await admin.from("villages")
    .select("id, owner, owner_name, guard, taken_at, paid_at, buildings, building, holder:players!villages_owner_fkey(alliance_id)")
    .in("id", CAPITAL_IDS).not("owner", "is", null);
  const out = { levels: [] as number[], guilds: [] as number[] };
  const t = now();
  for (const r of (data ?? []) as Row[]) {
    const ours = r.owner === userId || (me !== null && me.alliance_id !== null && Number(r.holder?.alliance_id) === me.alliance_id);
    const info = villageInfo(r.id);
    if (!ours || !info) continue;
    out.levels.push(info.level);
    const guild = rules.capitals.buildingLevel(villageState(r), "guildhall", t);
    if (guild > 0) out.guilds.push(guild);
  }
  return out;
}

/** Whether this player's keep (and, for a capital, alliance) has room for one more of these. */
async function hasRoom(userId: string, info: VillageInfo): Promise<boolean> {
  const { data: p } = await admin.from("players").select("level").eq("user_id", userId).maybeSingle();
  if (!p) return false;
  const held = await holdings(userId);
  const vr = rulesFor(rules, info);
  if (vr.checkRoom(Number(p.level), info.capital ? held.capitals : held.villages) !== "") return false;
  return !(vr instanceof CapitalRules) || vr.checkAlliance((await allianceCapitals(userId)).levels.length) === "";
}

/** The village an order names, as act() needs it, with its row. */
async function findVillage(id: unknown, userId: string): Promise<{ target: VillageTarget; row: Row } | null> {
  const info = villageInfo(id);
  if (!info) return null;
  await ensureVillages();
  const { data: row } = await admin.from("villages").select(`${VILLAGE_COLUMNS}, holder:players!villages_owner_fkey(alliance_id)`)
    .eq("id", info.id).maybeSingle();
  if (!row) return null;
  const held = await holdings(userId);
  const me = await store.player(userId);
  const ally = row.owner !== null && row.owner !== userId && me !== null && me.alliance_id !== null &&
    Number((row as Row).holder?.alliance_id) === me.alliance_id;
  const target: VillageTarget = { info, state: villageState(row), ally, held: info.capital ? held.capitals : held.villages };
  if (info.capital) target.allianceHeld = (await allianceCapitals(userId)).levels.length;
  return { target, row };
}

/** Takes what this player's villages made since they were last paid; the castle gets it with this request. */
async function collectVillages(userId: string): Promise<Record<string, number>> {
  const { data } = await admin.from("villages").select(VILLAGE_COLUMNS).eq("owner", userId);
  const income: Record<string, number> = {};
  const t = now();
  for (const r of data ?? []) {
    const info = villageInfo(r.id);
    if (!info) continue;
    const state = villageState(r);
    const paid = rulesFor(rules, info).collect(info, state, t);
    if (paid.amount <= 0) continue;
    // Only if nobody else collected or took it meanwhile.
    const { data: took } = await admin.from("villages").update({ paid_at: paid.paid_at, version: r.version + 1 })
      .eq("id", r.id).eq("version", r.version).eq("owner", userId).select("id");
    if (took && took.length > 0) income[info.resource] = (income[info.resource] ?? 0) + paid.amount;
  }
  return income;
}

/** Soldiers walking home from a village to a player's castle (a raids row on its way back). */
async function sendHome(owner: string, info: VillageInfo, survivors: Record<string, number>, t: number) {
  if (Object.keys(survivors).length === 0) return;
  const { data: p } = await admin.from("players").select("name, home_x, home_y").eq("user_id", owner).maybeSingle();
  if (!p) return;
  const travel = rules.barons.marchTime(Math.hypot(info.position[0] - p.home_x, info.position[1] - p.home_y));
  await admin.from("raids").insert({
    attacker: owner, defender: null, attacker_name: p.name, defender_name: info.name, village: info.id, mission: "return",
    army: {}, from_x: p.home_x, from_y: p.home_y, to_x: info.position[0], to_y: info.position[1],
    depart: t, arrive: t, back: t + travel, state: "home", survivors,
  });
}

/** Fights every battle at a village that is due, and lets guards that have arrived move in. */
async function resolveVillageRaids() {
  const { data: due } = await admin.from("raids").select("*").not("village", "is", null).eq("state", "out").lte("arrive", now())
    .order("arrive").limit(50);
  for (const row of due ?? []) {
    // Take it, so that no other request resolves it as well.
    const { data: claimed } = await admin.from("raids").update({ state: "fighting" })
      .eq("id", row.id).eq("state", "out").select("id");
    if (!claimed || claimed.length === 0) continue;
    const raid = raidFromRow(row);
    const info = villageInfo(raid.village);
    if (!info) {
      await admin.from("raids").update({ state: "home", survivors: raid.army }).eq("id", row.id);
      continue;
    }
    await ensureVillages();
    // Whether the attacker's keep has room for one more village (or capital).
    const room = await hasRoom(row.attacker, info);
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const { data: v } = await admin.from("villages").select(VILLAGE_COLUMNS).eq("id", info.id).maybeSingle();
      if (!v) break;
      const before = villageState(v);
      const out = resolveVillageRaid(rules, info, before, raid, room);
      const captured = out.state.owner !== before.owner;
      // A capital taken: its old holder's hold points count up to the battle.
      const scoredAt = Number(v.scored_at ?? 0);
      const { data: saved } = await admin.from("villages").update({
        owner: captured ? row.attacker : v.owner, owner_name: captured ? out.state.owner : v.owner_name, guard: out.state.guard,
        taken_at: out.state.taken_at, paid_at: out.state.paid_at, buildings: out.state.buildings ?? {},
        building: out.state.building ?? null, ...(captured ? { scored_at: Math.max(scoredAt, Math.floor(raid.arrive)) } : {}),
        version: v.version + 1,
      }).eq("id", info.id).eq("version", v.version).eq("scored_at", scoredAt).select("id");
      if (!saved || saved.length === 0) continue;
      if (info.capital && out.attackerReport?.result === "fought") {
        await warPointsForBattle(info, v, row.attacker, raid.arrive, captured, out.attackerReport.winner === "b",
          out.attackerReport.a ?? {});
      }
      if (out.attackerReport) await saveReports(row.attacker, [out.attackerReport]);
      if (out.ownerReport && v.owner) await saveReports(v.owner, [out.ownerReport]);
      if (captured && v.owner) await sendHome(v.owner, info, out.guardHome, raid.arrive);
      const stays = Object.keys(out.survivors).length === 0 && out.attackerReport?.result !== "fought";
      await admin.from("raids").update(stays ? { state: "done" }
        : { state: "home", survivors: out.survivors, loot: out.loot, ...(out.lead ? { lead: out.lead } : {}) }).eq("id", row.id);
      break;
    }
  }
}

/** Your guards leave a village for home ("recall_guard"), and with "abandon_village" the village goes back to the militia. */
async function villageOrder(userId: string, body: Record<string, unknown>): Promise<string> {
  const info = villageInfo(body.village);
  if (!info) return "There's no such village.";
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: v } = await admin.from("villages").select(VILLAGE_COLUMNS).eq("id", info.id).eq("owner", userId).maybeSingle();
    if (!v) return "That village isn't yours.";
    const guard = v.guard ?? {};
    const abandon = body.action === "abandon_village";
    if (!abandon && Object.keys(guard).length === 0) return "No soldiers guard that village.";
    const t = now();
    const scoredAt = Number(v.scored_at ?? 0);
    // A capital's town buildings stay in the town; one still going up is lost. Its hold points count up to now.
    const { data: saved } = await admin.from("villages")
      .update(abandon ? { owner: null, owner_name: null, guard: {}, taken_at: 0, paid_at: 0,
        buildings: settled(villageState(v), t).buildings ?? {}, building: null, scored_at: Math.max(scoredAt, Math.floor(t)), version: v.version + 1 }
        : { guard: {}, version: v.version + 1 })
      .eq("id", info.id).eq("version", v.version).eq("scored_at", scoredAt).select("id");
    if (!saved || saved.length === 0) continue;
    if (abandon && info.capital) {
      const alliance = await warAlliance(userId);
      if (alliance) await saveWarPoints(holdEntries(warRules, info, alliance, Math.max(scoredAt, Number(v.taken_at)), t));
    }
    await sendHome(userId, info, guard, now());
    return "";
  }
  return "The server is busy, try again.";
}

/**
 * Saves a capital's town building under way, if its row is still as act()
 * saw it (`version`): nobody took the capital or collected from it meanwhile.
 */
async function startTownBuilding(userId: string, info: VillageInfo, state: VillageState, version: number): Promise<boolean> {
  const { data: saved } = await admin.from("villages")
    .update({ buildings: state.buildings ?? {}, building: state.building ?? null, version: version + 1 })
    .eq("id", info.id).eq("owner", userId).eq("version", version).select("id");
  return (saved ?? []).length > 0;
}

/** Gives a player's castle back what an order paid for that couldn't go through; the player as saved then. */
async function refund(userId: string, cost: Record<string, number>): Promise<PlayerState | null> {
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (!row) return null;
    const { version, ...stored } = row as PlayerState & { version: number };
    const castle = structuredClone(stored.castle);
    castle.resources = { ...castle.resources };
    for (const r of Object.keys(cost)) castle.resources[r] = Number(castle.resources[r] ?? 0) + cost[r];
    const { data: saved } = await admin.from("players").update({ castle, version: version + 1 })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saved && saved.length > 0) return { ...stored, castle };
  }
  return null;
}

/** Gives back the gear or gems of a market offer that couldn't be stored; the new state, or null. */
async function refundItem(userId: string, offer: Pick<Offer, "give" | "give_amount" | "item">): Promise<PlayerState | null> {
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (!row) return null;
    const { version, ...stored } = row as PlayerState & { version: number };
    const castle = structuredClone(stored.castle);
    const state = CastleState.fromDict(rules.buildings, castle);
    receiveItem(state, offer);
    const saved = { ...castle, armoury: state.armoury };
    const { data: done } = await admin.from("players").update({ castle: saved, version: version + 1 })
      .eq("user_id", userId).eq("version", version).select("version");
    if (done && done.length > 0) return { ...stored, castle: saved };
  }
  return null;
}

/** The columns other players can see, worked out from a player's state. */
function publicColumns(state: PlayerState) {
  return { level: castleLevel(state.castle), might: might(state.castle, pvp), ...seasonColumns(state.castle, seasonRules),
    ...tourneyColumns(state.castle, seasonRules) };
}

/** Every spot a castle stands on: players' homes and their outposts. */
async function takenSpots(): Promise<[number, number][] | null> {
  const { data, error } = await admin.from("players").select("home_x, home_y, outpost_x:outpost->x, outpost_y:outpost->y");
  if (error) return null;
  const taken: [number, number][] = [];
  for (const r of data ?? []) {
    taken.push([r.home_x, r.home_y]);
    if (r.outpost_x !== null && r.outpost_x !== undefined) taken.push([Number(r.outpost_x), Number(r.outpost_y)]);
  }
  return taken;
}

async function saveReports(userId: string, reports: unknown[]) {
  if (reports.length === 0) return;
  // deno-lint-ignore no-explicit-any
  await admin.from("reports").insert(reports.map((r: any) => ({ user_id: userId, at: r.at, report: r })));
}

/** Unloads every cart that has arrived, sent by or to this player, into the receiver's castle. */
async function resolveAid(userId: string) {
  const { data: due } = await admin.from("aid").select("*").eq("kind", "resources").eq("state", "out").lte("arrive", now())
    .or(`sender.eq.${userId},receiver.eq.${userId}`).order("arrive");
  for (const row of due ?? []) {
    // Take the cart, so that no other request unloads it as well.
    const { data: claimed } = await admin.from("aid").update({ state: "delivering" })
      .eq("id", row.id).eq("state", "out").select("id");
    if (!claimed || claimed.length === 0) continue;
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const { data: target } = await admin.from("players").select(COLUMNS).eq("user_id", row.receiver).maybeSingle();
      if (!target) break;
      const { version, ...stored } = target as PlayerState & { version: number };
      const out = deliver(rules, stored, aidFromRow(row));
      const { data: saved } = await admin.from("players")
        .update({ ...out.receiver, ...publicColumns(out.receiver), version: version + 1, updated_at: new Date().toISOString() })
        .eq("user_id", row.receiver).eq("version", version).select("version");
      if (!saved || saved.length === 0) continue;
      await saveReports(row.receiver, [...out.campReports, out.receiverReport]);
      await saveReports(row.sender, [out.senderReport]);
      break;
    }
    await admin.from("aid").update({ state: "done" }).eq("id", row.id);
  }
}

type SentAgents = { success: boolean; mission: string; resource: string; stolen: Record<string, number>; target: string };

/** The target's side of a sabotage mission: what the agents took or burned there, and word to both sides. */
async function agentsArrive(targetId: string, senderId: string, senderName: string, sender: PlayerState, sent: SentAgents,
  agents: number, t: number) {
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(COLUMNS).eq("user_id", targetId).maybeSingle();
    if (!row) return;
    const { version, ...stored } = row as PlayerState & { version: number };
    const out = sabotagePlayer(rules, sabotageRules, stored, sent, senderName, castleLevel(sender.castle), agents, t);
    const { data: saved } = await admin.from("players")
      .update({ ...out.target, ...publicColumns(out.target), version: version + 1, updated_at: new Date().toISOString() })
      .eq("user_id", targetId).eq("version", version).select("version");
    if (!saved || saved.length === 0) continue;
    await saveReports(targetId, [...out.campReports, out.targetReport]);
    await saveReports(senderId, [out.senderReport]);
    return;
  }
}

/** Allied defenders standing in this player's castle at time `t`. */
async function helpersAt(userId: string, t: number): Promise<Row[]> {
  const { data } = await admin.from("aid").select("*").eq("receiver", userId).eq("kind", "troops").eq("state", "out")
    .lte("arrive", t).gt("leave", t).order("id");
  return data ?? [];
}

/** Fights every battle between players that is due and involves this player. */
async function resolveRaids(userId: string) {
  const { data: due } = await admin.from("raids").select("*").eq("state", "out").lte("arrive", now()).is("village", null)
    .or(`attacker.eq.${userId},defender.eq.${userId}`).order("arrive");
  for (const row of due ?? []) {
    // Take the battle, so that no other request fights it as well.
    const { data: claimed } = await admin.from("raids").update({ state: "fighting" })
      .eq("id", row.id).eq("state", "out").select("id");
    if (!claimed || claimed.length === 0) continue;
    const raid = raidFromRow(row);
    const helpers = await helpersAt(row.defender, raid.arrive);
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const { data: target } = await admin.from("players").select(COLUMNS).eq("user_id", row.defender).maybeSingle();
      if (!target) break;
      const { version, ...stored } = target as PlayerState & { version: number };
      const outcome = fightRaid(rules, pvp, stored, raid, helpers.map((h) => h.army));
      const { data: saved } = await admin.from("players")
        .update({ ...outcome.defender, ...publicColumns(outcome.defender), version: version + 1, updated_at: new Date().toISOString() })
        .eq("user_id", row.defender).eq("version", version).select("version");
      if (!saved || saved.length === 0) continue;
      if (helpers.length > 0) outcome.defenderReport.helped_by = [...new Set(helpers.map((h) => String(h.sender_name)))];
      await saveReports(row.defender, [...outcome.campReports, outcome.defenderReport]);
      await saveReports(row.attacker, [outcome.attackerReport]);
      await admin.from("raids").update({ state: "home", survivors: outcome.survivors, loot: outcome.loot,
        won: outcome.attackerReport.winner === "a", ...(outcome.lead ? { lead: outcome.lead } : {}) }).eq("id", row.id);
      // Allied defenders who fought: what is left of them, and a word to whoever sent them.
      for (const [i, h] of helpers.entries()) {
        const left = outcome.helpers[i];
        const lost: Record<string, number> = {};
        for (const unit of Object.keys(h.army)) if (h.army[unit] - (left[unit] ?? 0) > 0) lost[unit] = h.army[unit] - (left[unit] ?? 0);
        await admin.from("aid").update(Object.keys(left).length > 0 ? { army: left } : { army: left, state: "done" }).eq("id", h.id);
        await saveReports(h.sender, [{ kind: "aid", event: "defended", name: h.receiver_name, at: raid.arrive,
          attacker: raid.attacker_name, held: outcome.attackerReport.winner === "b", lost }]);
      }
      break;
    }
  }
}

// --- The market (market.ts) ------------------------------------------------------

function offerFromRow(r: Row): Offer {
  return { id: Number(r.id), seller_name: r.seller_name, give: r.give, give_amount: r.give_amount, want: r.want,
    want_amount: r.want_amount, proceeds: r.proceeds, posted: r.posted, expires: r.expires, ...(r.item ? { item: r.item } : {}) };
}

/** The market as the market screen shows it: everyone else's open offers, yours, your recent sales and the going rates. */
async function marketView(userId: string) {
  const t = now();
  const [{ data: open }, { data: mine }, { data: sales }] = await Promise.all([
    admin.from("market_offers").select("*, holder:players!market_offers_seller_fkey(alliance:alliances!players_alliance_id_fkey(tag))")
      .eq("state", "open").gt("expires", t).neq("seller", userId).order("id", { ascending: false }).limit(OFFERS_SHOWN),
    admin.from("market_offers").select("*").eq("seller", userId).order("id", { ascending: false }).limit(20),
    admin.from("market_offers").select("give, give_amount, want, want_amount").not("sold_at", "is", null)
      .order("sold_at", { ascending: false }).limit(SALES_COUNTED),
  ]);
  return {
    offers: (open ?? []).map((r: Row) => ({ ...offerFromRow(r), tag: r.holder?.alliance?.tag ?? "" })),
    mine: (mine ?? []).filter((r: Row) => r.state === "open" && r.expires > t).map(offerFromRow),
    sold: (mine ?? []).filter((r: Row) => r.state === "sold" || r.state === "paid").slice(0, 10)
      .map((r: Row) => ({ ...offerFromRow(r), buyer_name: r.buyer_name ?? "", sold_at: r.sold_at })),
    rates: goingRates(sales ?? []),
  };
}

/** Takes the proceeds of your sales and the goods of your cancelled and expired offers; your castle gets them with this request. */
async function collectMarket(userId: string): Promise<{ income: Record<string, number>; items: Item[]; reports: MarketReport[] }> {
  const t = now();
  const { data } = await admin.from("market_offers").select("*").eq("seller", userId).in("state", ["open", "buying", "sold", "cancelled"]);
  const income: Record<string, number> = {};
  const items: Item[] = [];
  const reports: MarketReport[] = [];
  for (const r of (data ?? []) as Row[]) {
    // A sale whose buyer never finished paying (their request failed) goes back up.
    if (r.state === "buying") {
      if (Number(r.sold_at) < t - STALE_PURCHASE) {
        await admin.from("market_offers").update({ state: "open", buyer: null, sold_at: null }).eq("id", r.id).eq("state", "buying");
      }
      continue;
    }
    if (r.state === "open" && r.expires > t) continue;
    // Only if no other request took it meanwhile (or, for an open offer, a buyer).
    const next = r.state === "sold" ? "paid" : "returned";
    const { data: took } = await admin.from("market_offers").update({ state: next }).eq("id", r.id).eq("state", r.state).select("id");
    if (!took || took.length === 0) continue;
    const [good, amount] = r.state === "sold" ? [r.want, r.proceeds] : [r.give, r.give_amount];
    // Gear comes back as itself; everything else (resources, Marks, gems) by the amount.
    if (r.state !== "sold" && r.item) items.push(r.item as Item);
    else income[good] = (income[good] ?? 0) + Number(amount);
    if (r.state === "open") {
      reports.push({ kind: "market", event: "expired", at: Number(r.expires), give: r.give, give_amount: r.give_amount,
        want: r.want, want_amount: r.want_amount, ...(r.item ? { item_name: String(r.item.name ?? "") } : {}) });
    }
  }
  return { income, items, reports };
}

/** Takes your offer down; its goods come home with this request. The error, or "". */
async function cancelOffer(userId: string, id: unknown): Promise<string> {
  const { data } = await admin.from("market_offers").update({ state: "cancelled" })
    .eq("id", Number(id)).eq("seller", userId).eq("state", "open").select("id");
  return data && data.length > 0 ? "" : "That offer is gone.";
}

/** Takes an open offer for this buyer, so nobody else can buy it meanwhile; the offer and its seller, or why not. */
async function takeOffer(userId: string, id: unknown): Promise<{ offer: Offer; seller: string } | string> {
  const { data: row } = await admin.from("market_offers").select("*").eq("id", Number(id)).eq("state", "open").maybeSingle();
  if (!row || row.expires <= now()) return "That offer is gone.";
  if (row.seller === userId) return "That's your own offer.";
  const { data: took } = await admin.from("market_offers").update({ state: "buying", buyer: userId, sold_at: now() })
    .eq("id", row.id).eq("state", "open").select("id");
  if (!took || took.length === 0) return "Someone else bought it first.";
  return { offer: offerFromRow(row), seller: row.seller };
}

/** Puts an offer this buyer took back up, when they couldn't pay for it after all. */
async function releaseOffer(userId: string, id: number) {
  await admin.from("market_offers").update({ state: "open", buyer: null, sold_at: null })
    .eq("id", id).eq("state", "buying").eq("buyer", userId);
}

/** Calls your defenders home from an ally; the error, or "" when done. */
async function recallDefenders(userId: string, id: unknown): Promise<string> {
  const { data: row } = await admin.from("aid").select("*").eq("id", Number(id)).eq("sender", userId).eq("kind", "troops")
    .eq("state", "out").maybeSingle();
  if (!row) return "There are no such defenders.";
  const times = recall(aidFromRow(row), now());
  if (typeof times === "string") return times;
  await admin.from("aid").update(times).eq("id", row.id).eq("state", "out");
  return "";
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
    target: { name: row.name, home: [row.home_x, row.home_y], protected: isProtected(row as PlayerState, pvp, now()),
      level: castleLevel((row as PlayerState).castle), ally },
    row,
  };
}

/** An alliance's tag from an embedded `alliance:alliances!players_alliance_id_fkey(tag)`, or "". The foreign key
 * is named because players also reach alliances through alliance_pending. */
function tagOf(r: Row): string {
  return r.alliance?.tag ?? "";
}

/** The player as chat sees them: name, alliance and its tag; null without a castle. */
async function speaker(userId: string): Promise<Speaker | null> {
  const me = await store.player(userId);
  if (me === null) return null;
  const a = me.alliance_id === null ? null : await store.alliance(me.alliance_id);
  return { user: userId, name: me.name, tag: a?.tag ?? "", alliance_id: a === null ? null : me.alliance_id };
}

/** A place in an Ember Horde's ranking: one more than the players of that run with more points (ties share it). */
async function hordeRank(key: number, points: number): Promise<number> {
  const { count } = await admin.from("players").select("user_id", { count: "exact", head: true })
    .eq("horde_key", key).gt("horde_points", points);
  return (count ?? 0) + 1;
}

// --- Seasons (server/rules/seasons.ts) ----------------------------------------

type SeasonRow = { alliance_id: number | null; season_key: number; season_points: number; last_season_key: number; last_season_points: number };

/** Every player who earned in season `key`, this season or the last. */
async function seasonRows(key: number): Promise<SeasonRow[] | null> {
  const { data, error } = await admin.from("players").select("alliance_id, season_key, season_points, last_season_key, last_season_points")
    .or(`season_key.eq.${key},last_season_key.eq.${key}`).limit(10000);
  return error ? null : (data ?? []) as SeasonRow[];
}

/** What a stored castle earned in the season before this one: {key, points}, or null. */
function lastSeasonOf(stored: PlayerState, t: number): { key: number; points: number; claimed: boolean } | null {
  const s = stored.castle.season;
  if (!s) return null;
  // Not yet rolled into this month: what it has now is last season's.
  if (s.key >= 0 && s.key !== seasonKey(t)) return { key: s.key, points: renown(stored.castle, seasonRules), claimed: false };
  return s.last && "key" in s.last ? s.last : null;
}

/** Your place and your alliance's in a season's ranking (0: not ranked). */
async function seasonPlaces(key: number, points: number, allianceId: number | null): Promise<{ player: number; alliance: number }> {
  const rows = await seasonRows(key);
  if (rows === null) return { player: 0, alliance: 0 };
  const standings = allianceStandings(rows, key);
  const at = allianceId === null ? -1 : standings.findIndex(([id]) => id === Number(allianceId));
  return { player: placeIn(rows, key, points), alliance: at < 0 ? 0 : at + 1 };
}

// --- Alliance wars (wars.ts) ------------------------------------------------

/** The alliance a player is in, as war points name it; null outside one. */
async function warAlliance(userId: string | null): Promise<WarAlliance | null> {
  if (!userId) return null;
  const { data } = await admin.from("players").select("alliance_id, alliance:alliances!players_alliance_id_fkey(name, tag)")
    .eq("user_id", userId).maybeSingle();
  if (!data || data.alliance_id === null || !data.alliance) return null;
  return { id: Number(data.alliance_id), name: String(data.alliance.name), tag: String(data.alliance.tag) };
}

async function saveWarPoints(entries: (WarEntry | null)[]) {
  const rows = entries.filter((e): e is WarEntry => e !== null);
  if (rows.length > 0) await admin.from("war_points").insert(rows);
}

/**
 * Gives each capital's holder's alliance its hold points up to the start of
 * this hour. Each capital is counted by whichever request comes first in the
 * hour: it moves the capital's scored_at only if nobody did meanwhile.
 */
async function scoreCapitals() {
  const t = now();
  if (hourStart(t) <= scoredUntil) return;
  const { data, error } = await admin.from("villages").select("id, owner, taken_at, scored_at").in("id", CAPITAL_IDS)
    .not("owner", "is", null);
  if (error) return;
  for (const r of (data ?? []) as Row[]) {
    const info = villageInfo(r.id);
    const due = holdDue(Number(r.scored_at), Number(r.taken_at), t);
    if (!info || !due) continue;
    const { data: saved } = await admin.from("villages").update({ scored_at: due.to })
      .eq("id", r.id).eq("owner", r.owner).eq("scored_at", r.scored_at).select("id");
    if (!saved || saved.length === 0) continue;
    const alliance = await warAlliance(r.owner);
    if (alliance) await saveWarPoints(holdEntries(warRules, info, alliance, due.from, due.to));
  }
  scoredUntil = hourStart(t);
}

/**
 * War points for a battle at a capital: when it was taken, its old holder's
 * alliance gets its hold points up to the battle and the attacker's alliance
 * the points for taking it (once a season); when its holder kept it, their
 * alliance gets points for the attackers who fell.
 */
async function warPointsForBattle(info: VillageInfo, before: Row, attacker: string, at: number, captured: boolean, held: boolean,
  attackers: Record<string, { start: number; lost: number }>) {
  if (captured) {
    const old = await warAlliance(before.owner);
    if (old) await saveWarPoints(holdEntries(warRules, info, old, Math.max(Number(before.scored_at ?? 0), Number(before.taken_at)), at));
    const mine = await warAlliance(attacker);
    if (mine) {
      const { count } = await admin.from("war_points").select("id", { count: "exact", head: true })
        .eq("season", seasonAt(warRules, at).start).eq("alliance_id", mine.id).eq("capital", info.id).eq("kind", "capture");
      await saveWarPoints([captureEntry(warRules, info, mine, at, (count ?? 0) > 0)]);
    }
  } else if (held && before.owner) {
    const holder = await warAlliance(before.owner);
    if (holder) await saveWarPoints([defenceEntry(warRules, info, holder, at, attackers)]);
  }
}

/** A season's standings, from war_standings. */
async function seasonStandings(season: number): Promise<Standing[]> {
  const { data } = await admin.from("war_standings").select("alliance_id, name, tag, points, captures, defences")
    .eq("season", season).gt("points", 0).order("points", { ascending: false }).limit(200);
  return ranked((data ?? []).map((r: Row) => ({ alliance_id: Number(r.alliance_id), name: String(r.name), tag: String(r.tag),
    points: Number(r.points), captures: Number(r.captures), defences: Number(r.defences) })));
}

/** The war screen (warBoard() in wars.ts) for this player. */
async function warView(userId: string) {
  await scoreCapitals();
  await ensureVillages();
  const t = now();
  const [current, last, { data: rows }, { data: me }] = await Promise.all([
    seasonStandings(seasonAt(warRules, t).start),
    seasonStandings(lastSeason(warRules, t).start),
    admin.from("villages").select("id, owner, owner_name, holder:players!villages_owner_fkey(alliance_id, alliance:alliances!players_alliance_id_fkey(tag))")
      .in("id", CAPITAL_IDS),
    admin.from("players").select("alliance_id, alliance_joined, war_claimed").eq("user_id", userId).maybeSingle(),
  ]);
  const byId = new Map(((rows ?? []) as Row[]).map((r) => [r.id, r]));
  const capitals: CapitalHold[] = CAPITALS.map((info) => {
    const r = byId.get(info.id);
    const owned = r !== undefined && r.owner !== null;
    const alliance = owned && r.holder?.alliance_id != null ? Number(r.holder.alliance_id) : null;
    return { id: info.id, name: info.name, level: info.level, owner: owned ? String(r.owner_name ?? "") : "",
      alliance_id: alliance, tag: owned ? String(r.holder?.alliance?.tag ?? "") : "" };
  });
  const member = me ? { alliance_id: me.alliance_id === null ? null : Number(me.alliance_id), joined: Number(me.alliance_joined),
    war_claimed: Number(me.war_claimed) } : null;
  return warBoard(warRules, t, current, last, capitals, member);
}

/** Gives this player their prize for their alliance's place in the last season; the error, or "" when done. */
async function claimWarPrize(userId: string): Promise<string> {
  const t = now();
  const last = lastSeason(warRules, t);
  const standings = await seasonStandings(last.start);
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(`alliance_id, alliance_joined, war_claimed, ${COLUMNS}`)
      .eq("user_id", userId).maybeSingle();
    if (!row) return "No castle yet.";
    const { version, alliance_id, alliance_joined, war_claimed, ...stored } = row as Row;
    const mine = alliance_id === null ? undefined : standings.find((s) => s.alliance_id === Number(alliance_id));
    const prize = checkClaim(warRules, { alliance_id: alliance_id === null ? null : Number(alliance_id),
      joined: Number(alliance_joined), war_claimed: Number(war_claimed) }, mine, t);
    if (typeof prize === "string") return prize;
    const castle = CastleState.fromDict(rules.buildings, stored.castle);
    givePrize(castle, prize);
    const state = { ...stored, castle: castle.toDict() } as PlayerState;
    const { data: saved } = await admin.from("players")
      .update({ castle: state.castle, war_claimed: last.start, ...publicColumns(state), version: version + 1,
        updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saved && saved.length > 0) return "";
  }
  return "The server is busy, try again.";
}

// --- Weekly alliance tournaments (tournaments.ts) ---------------------------

/**
 * A week's tournament as stored: its entrants and the scores of the rounds
 * already over. This week's bracket is drawn by the first request after the
 * week starts; an earlier week without one had no tournament.
 */
async function tournamentOf(week: number, t: number): Promise<{ entrants: Entrant[]; results: Record<string, Record<string, number>> }> {
  const read = async () => (await admin.from("tournaments").select("entrants, results").eq("week", week).maybeSingle()).data;
  let row = await read();
  if (!row && week === weekAt(tourneyRules, t)) {
    const { data } = await admin.from("alliance_summaries").select("id, name, tag, members, might");
    const entrants = draw(tourneyRules, (data ?? []).map((r: Row) => ({ id: Number(r.id), name: String(r.name), tag: String(r.tag),
      members: Number(r.members), might: Number(r.might) })));
    await admin.from("tournaments").upsert({ week, entrants, results: {}, drawn_at: t }, { onConflict: "week", ignoreDuplicates: true });
    row = await read();
  }
  return { entrants: (row?.entrants ?? []) as Entrant[], results: (row?.results ?? {}) as Record<string, Record<string, number>> };
}

/** A week's bracket as it stands at `t`. Rounds that are over keep the scores they ended with (stored the first time they're read). */
async function tournamentRounds(week: number, t: number): Promise<{ entrants: Entrant[]; rounds: Round[] }> {
  const { entrants, results } = await tournamentOf(week, t);
  if (entrants.length === 0) return { entrants, rounds: [] };
  const { data } = await admin.from("players")
    .select("alliance_id, alliance_joined, tourney_key, tourney_points, last_tourney_key, last_tourney_points")
    .in("alliance_id", entrants.map((e) => e.id)).limit(10000);
  const rows = (data ?? []) as TourneyRow[];
  const settled = { ...results };
  let fresh = false;
  const rounds = bracket(tourneyRules, week, entrants, t, (start) => {
    const kept = settled[String(start)];
    if (kept) return new Map(Object.entries(kept).map(([id, n]) => [Number(id), Number(n)]));
    return roundScores(rows, start);
  });
  for (const r of rounds) {
    if (t < r.end || settled[String(r.start)]) continue;
    settled[String(r.start)] = Object.fromEntries(roundScores(rows, r.start));
    fresh = true;
  }
  if (fresh) await admin.from("tournaments").update({ results: settled }).eq("week", week);
  return { entrants, rounds };
}

async function tourneyMember(userId: string): Promise<TourneyMember | null> {
  const { data: me } = await admin.from("players").select("alliance_id, alliance_joined, tourney_claimed").eq("user_id", userId).maybeSingle();
  return me ? { alliance_id: me.alliance_id === null ? null : Number(me.alliance_id), joined: Number(me.alliance_joined),
    claimed: Number(me.tourney_claimed) } : null;
}

/** The tournament screen (tourneyBoard() in tournaments.ts) for this player. */
async function tournamentView(userId: string) {
  const t = now();
  const week = weekAt(tourneyRules, t);
  const { entrants, rounds } = await tournamentRounds(week, t);
  const prizeWeek = claimableWeek(tourneyRules, t);
  const prize = prizeWeek === week ? { week, rounds } : { week: prizeWeek, rounds: (await tournamentRounds(prizeWeek, t)).rounds };
  return tourneyBoard(tourneyRules, t, week, entrants, rounds, await tourneyMember(userId), prize);
}

/** Gives this player their prize for how far their alliance got in the last finished tournament; the error, or "" when done. */
async function claimTournamentPrize(userId: string): Promise<string> {
  const t = now();
  const week = claimableWeek(tourneyRules, t);
  const { rounds } = await tournamentRounds(week, t);
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(`alliance_id, alliance_joined, tourney_claimed, ${COLUMNS}`)
      .eq("user_id", userId).maybeSingle();
    if (!row) return "No castle yet.";
    const { version, alliance_id, alliance_joined, tourney_claimed, ...stored } = row as Row;
    const prize = checkTourneyClaim(tourneyRules, { alliance_id: alliance_id === null ? null : Number(alliance_id),
      joined: Number(alliance_joined), claimed: Number(tourney_claimed) }, week, rounds);
    if (typeof prize === "string") return prize;
    const castle = CastleState.fromDict(rules.buildings, stored.castle);
    givePrize(castle, prize);
    const state = { ...stored, castle: castle.toDict() } as PlayerState;
    const { data: saved } = await admin.from("players")
      .update({ castle: state.castle, tourney_claimed: week, ...publicColumns(state), version: version + 1,
        updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saved && saved.length > 0) return "";
  }
  return "The server is busy, try again.";
}

// --- The game owner's tools (admin.ts) --------------------------------------

async function loadCalendar(): Promise<EventRules> {
  const { data } = await admin.from("event_overrides").select("event, starts_at, ends_at").gt("ends_at", now() - OVERRIDES_KEPT);
  return withOverrides(eventRules, (data ?? []).map((r: Row): EventOverride =>
    ({ event: r.event, start: Number(r.starts_at), end: Number(r.ends_at) })));
}

async function isAdmin(userId: string): Promise<boolean> {
  const { data } = await admin.from("admins").select("user_id").eq("user_id", userId).maybeSingle();
  return data !== null;
}

async function adminView() {
  const [{ data: names }, { data: log }] = await Promise.all([
    admin.from("players").select("name").order("name").limit(PLAYERS_SHOWN),
    admin.from("admin_log").select("at, action, details").order("id", { ascending: false }).limit(REPORTS_SHOWN),
  ]);
  return {
    admin: { is_admin: true, events: adminEvents(calendar, now()), players: (names ?? []).map((r: Row) => r.name), log: log ?? [] },
  };
}

/** Puts a gift in one player's castle and leaves them a report; false if their castle kept changing. */
async function giveTo(userId: string, gift: Gift): Promise<boolean> {
  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (!row) return false;
    const { version, ...stored } = row as Row;
    const castle = CastleState.fromDict(rules.buildings, stored.castle);
    giveCastle(castle, gift);
    const state = { ...stored, castle: castle.toDict() } as PlayerState;
    const { data: saved } = await admin.from("players")
      .update({ castle: state.castle, ...publicColumns(state), version: version + 1, updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (!saved || saved.length === 0) continue;
    await saveReports(userId, [giftReport(gift, now())]);
    return true;
  }
  return false;
}

async function adminOrder(userId: string, body: Record<string, unknown>) {
  if (!(await isAdmin(userId))) {
    return body.action === "admin"
      ? { ok: true, now: now(), error: "", result: { admin: { is_admin: false } } }
      : { ok: true, now: now(), error: NOT_ADMIN };
  }
  const t = now();
  let error = "";
  let details: Record<string, unknown> | null = null;
  switch (body.action) {
    case "admin":
      break;
    case "admin_start_event":
    case "admin_stop_event": {
      const o = body.action === "admin_start_event" ? startEvent(calendar, body.event, body.hours, t) : stopEvent(calendar, body.event, t);
      if (typeof o === "string") {
        error = o;
        break;
      }
      const { error: saveError } = await admin.from("event_overrides").upsert({ event: o.event, starts_at: o.start, ends_at: o.end });
      if (saveError) {
        error = "The server couldn't change the calendar.";
        break;
      }
      calendar = withOverrides(eventRules,
        [...(calendar.overrides ?? []).filter((x) => x.event !== o.event || x.start !== o.start), o]);
      details = { ...o };
      break;
    }
    case "admin_give": {
      const gift = checkGift(rules.buildings.resources, (u) => rules.buildings.hasUnit(u), body.resources, body.troops);
      if (typeof gift === "string") {
        error = gift;
        break;
      }
      const everyone = body.target === "*";
      let targets: Row[] = [];
      if (everyone) {
        const { data } = await admin.from("players").select("user_id, name");
        targets = data ?? [];
      } else if (typeof body.target === "string" && body.target.trim() !== "") {
        const { data } = await admin.from("players").select("user_id, name")
          .ilike("name", body.target.trim().replace(/[%_\\]/g, "\\$&")).maybeSingle();
        if (data) targets = [data];
      }
      if (targets.length === 0) {
        error = everyone ? "There are no players yet." : "There's no player by that name.";
        break;
      }
      let given = 0;
      for (const p of targets) if (await giveTo(p.user_id, gift)) given++;
      if (given < targets.length) error = `${targets.length - given} castles were busy and got nothing. Try them again.`;
      details = { target: everyone ? "everyone" : targets[0].name, castles: given, ...gift };
      break;
    }
    default:
      error = "Unknown order.";
  }
  if (details !== null) await admin.from("admin_log").insert({ admin: userId, at: t, action: body.action, details });
  return { ok: true, now: now(), error, result: await adminView() };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
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
  calendar = await loadCalendar();
  if (typeof body.action === "string" && body.action.startsWith("admin")) return reply(await adminOrder(userId, body));

  if (body.action === "join") {
    const why = checkName(body.name);
    if (why !== "") return reply({ ok: false, error: why });
    // Another player may take the same spot at the same moment; then try another.
    for (let attempt = 0; attempt < RETRIES; attempt++) {
      const spots = await takenSpots();
      if (spots === null) return reply({ ok: false, error: "The server couldn't create your castle." }, 500);
      const spot = pickSpot(world as World, spots);
      if (spot === null) return reply({ ok: false, error: "The world is full. Try again later." });
      // A castle founded during a Baron Invasion meets its invaders straight away.
      const state = hordeArrives(invade(newPlayer(rules, world as World, String(body.name), now(), spot, pvp), calendar, world as World, now()),
        calendar, world as World, now());
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
      .select("name, home_x, home_y, level, protected_until, alliance_id, alliance:alliances!players_alliance_id_fkey(tag), "
        + "outpost_name:outpost->>name, outpost_x:outpost->x, outpost_y:outpost->y, title:castle->achievements->>title")
      .neq("user_id", userId).limit(PLAYERS_SHOWN);
    if (error) return reply({ ok: false, error: "The server couldn't load the map." }, 500);
    const me = await store.player(userId);
    const t = now();
    const players = (data ?? []).map((p: Row) => ({
      name: p.name, home_x: p.home_x, home_y: p.home_y, level: p.level,
      protected: p.protected_until > t && p.level < pvp.protection_until_keep,
      tag: tagOf(p), title: p.title ?? "", ally: p.alliance_id !== null && me !== null && Number(p.alliance_id) === me.alliance_id,
      outpost: p.outpost_x === null || p.outpost_x === undefined ? null
        : { name: p.outpost_name, x: Number(p.outpost_x), y: Number(p.outpost_y) },
    }));
    return reply({ ok: true, now: t, error: "", players });
  }

  if (body.action === "view_castle") {
    // Only looking: nothing of anyone's castle changes, and it costs nothing.
    const found = await findTarget(body.target, userId);
    if (found === null) return reply({ ok: false, error: "There's no player by that name." });
    const result = castleView(rules, found.row as PlayerState, now(), body.outpost === true);
    if (result === null) return reply({ ok: false, error: "They have no outpost." });
    return reply({ ok: true, now: now(), error: "", result });
  }

  if (body.action === "tournament") {
    return reply({ ok: true, now: now(), error: "", result: { tournament: await tournamentView(userId) } });
  }

  if (body.action === "war_board") {
    return reply({ ok: true, now: now(), error: "", result: { war: await warView(userId) } });
  }

  if (body.action === "leaderboard") {
    const shown = "name, level, might, barons_beaten, alliance:alliances!players_alliance_id_fkey(tag), title:castle->achievements->>title";
    const { data, error } = await admin.from("players").select(shown)
      .order("might", { ascending: false }).order("barons_beaten", { ascending: false }).order("name")
      .limit(RANKS_SHOWN);
    const { data: mine } = await admin.from("players").select(shown).eq("user_id", userId).maybeSingle();
    const flat = (r: Row) => ({ name: r.name, level: r.level, might: r.might, barons_beaten: r.barons_beaten, tag: tagOf(r),
      title: r.title ?? "" });
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

  if (body.action === "season_board") {
    // This month's best players and alliances, and where you and your last season stand.
    const t = now();
    const key = seasonKey(t);
    const { data, error } = await admin.from("players").select("name, season_points, alliance:alliances!players_alliance_id_fkey(tag)")
      .eq("season_key", key).gt("season_points", 0).order("season_points", { ascending: false }).order("name").limit(RANKS_SHOWN);
    const rows = await seasonRows(key);
    const meRow = await admin.from("players").select(COLUMNS + ", alliance_id").eq("user_id", userId).maybeSingle();
    if (error || rows === null || meRow.error) return reply({ ok: false, error: "The server couldn't load the season." }, 500);
    const mine = meRow.data as (PlayerState & { alliance_id: number | null }) | null;
    const standings = allianceStandings(rows, key).slice(0, 5);
    const names = standings.length === 0 ? [] : (await admin.from("alliances").select("id, tag, name").in("id", standings.map(([id]) => id))).data ?? [];
    const alliances = standings.map(([id, points]) => {
      const a = names.find((n: Row) => Number(n.id) === id);
      return { tag: a?.tag ?? "", name: a?.name ?? "", points };
    });
    let me = null;
    let last = {};
    if (mine) {
      const fresh = mine.castle.season?.key === key;
      const points = fresh ? renown(mine.castle, seasonRules) : 0;
      me = { points, place: points > 0 ? placeIn(rows, key, points) : 0 };
      const prev = lastSeasonOf(mine, t);
      if (prev) {
        const places = await seasonPlaces(prev.key, prev.points, mine.alliance_id);
        last = { key: prev.key, points: prev.points, place: places.player, alliance_place: places.alliance, claimed: prev.claimed };
      }
    }
    const players = (data ?? []).map((r: Row) => ({ name: r.name, points: r.season_points, tag: tagOf(r) }));
    return reply({ ok: true, now: t, error: "", result: { key, end: seasonEnd(key), players, alliances, me, last } });
  }

  if (body.action === "event_board") {
    // The Baron Invasion on now (or the last one): the players with the most event points in it.
    const inv = lastInvasion(calendar, now());
    const key = inv?.start ?? -1;
    const shown = "name, event_key, event_points, alliance:alliances!players_alliance_id_fkey(tag)";
    const { data, error } = await admin.from("players").select(shown).eq("event_key", key).gt("event_points", 0)
      .order("event_points", { ascending: false }).order("name").limit(RANKS_SHOWN);
    if (error) return reply({ ok: false, error: "The server couldn't load the event leaderboard." }, 500);
    const { data: mine } = await admin.from("players").select(shown).eq("user_id", userId).maybeSingle();
    const flat = (r: Row) => ({ name: r.name, points: r.event_points, tag: tagOf(r) });
    const me = mine && mine.event_key === key && mine.event_points > 0 ? flat(mine) : null;
    let rank = 0;
    if (me) {
      const { count } = await admin.from("players").select("user_id", { count: "exact", head: true })
        .eq("event_key", key).gt("event_points", me.points);
      rank = (count ?? 0) + 1;
    }
    const { count: total } = await admin.from("players").select("user_id", { count: "exact", head: true })
      .eq("event_key", key).gt("event_points", 0);
    return reply({ ok: true, now: now(), error: "",
      result: { event: inv ?? null, players: (data ?? []).map(flat), me, rank, total: total ?? 0 } });
  }

  if (body.action === "horde_board") {
    // The Ember Horde on now (or the last one): the players with the most horde points in it, your rank and your prize.
    const run = lastHorde(calendar, now());
    const key = run?.start ?? -1;
    const shown = "name, horde_key, horde_points, alliance:alliances!players_alliance_id_fkey(tag)";
    const { data, error } = await admin.from("players").select(shown).eq("horde_key", key).gt("horde_points", 0)
      .order("horde_points", { ascending: false }).order("name").limit(RANKS_SHOWN);
    if (error) return reply({ ok: false, error: "The server couldn't load the horde ranking." }, 500);
    const { data: mine } = await admin.from("players").select(shown).eq("user_id", userId).maybeSingle();
    const flat = (r: Row) => ({ name: r.name, points: r.horde_points, tag: tagOf(r) });
    const me = mine && Number(mine.horde_key) === key && mine.horde_points > 0 ? flat(mine) : null;
    const rank = me ? await hordeRank(key, me.points) : 0;
    const { count: total } = await admin.from("players").select("user_id", { count: "exact", head: true })
      .eq("horde_key", key).gt("horde_points", 0);
    return reply({ ok: true, now: now(), error: "",
      result: { event: run ?? null, players: (data ?? []).map(flat), me, rank, total: total ?? 0,
        prize: me && run?.horde ? prizeFor(run.horde.prizes, rank) ?? null : null } });
  }

  if (body.action === "chat" || body.action === "chat_send") {
    const who = await speaker(userId);
    if (who === null) return reply({ ok: false, error: "No castle yet.", needs_join: true });
    const error = body.action === "chat_send" ? await send(chat, who, body, now()) : "";
    return reply({ ok: true, now: now(), error, result: await chatView(chat, who, body.after) });
  }

  if (typeof body.action === "string" && MAIL_ORDERS.has(body.action)) {
    const me = await store.player(userId);
    if (me === null) return reply({ ok: false, error: "No castle yet.", needs_join: true });
    let error = "";
    if (body.action === "mail_send") {
      const a = me.alliance_id === null ? null : await store.alliance(me.alliance_id);
      error = await sendLetter(mail, directory, { user: userId, name: me.name, alliance_id: a === null ? null : me.alliance_id,
        tag: a?.tag ?? "", role: me.role }, body, now());
    } else if (body.action !== "mail") {
      error = await mailOrder(mail, userId, body);
    }
    return reply({ ok: true, now: now(), error, result: await mailView(mail, userId, body) });
  }

  if (typeof body.action === "string" && ALLIANCE_ORDERS.has(body.action)) {
    const error = await handle(store, allianceRules, userId, body, now());
    return reply({ ok: true, now: now(), error, result: await allianceView(store, allianceRules, userId) });
  }

  if (body.action === "market") {
    if ((await store.player(userId)) === null) return reply({ ok: false, error: "No castle yet.", needs_join: true });
    return reply({ ok: true, now: now(), error: "", result: await marketView(userId) });
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

  // Calling defenders home changes no castle: do it, then answer like "state".
  let recalled = "";
  if (body.action === "recall_defenders") {
    recalled = await recallDefenders(userId, body.id);
    body = { action: "state" };
  }

  // Taking an offer down changes no castle until its goods are collected below.
  let marketError = "";
  if (body.action === "cancel_offer") {
    marketError = await cancelOffer(userId, body.id);
    body = { action: "state", market: true };
  }

  await resolveAid(userId);
  await resolveRaids(userId);
  await resolveVillageRaids();
  await scoreCapitals();
  // A war prize changes only your castle: give it, then answer like "state".
  let warError = "";
  if (body.action === "claim_war_prize") {
    warError = await claimWarPrize(userId);
    body = { action: "state" };
  }
  if (body.action === "claim_tournament_prize") {
    warError = await claimTournamentPrize(userId);
    body = { action: "state" };
  }
  // What your villages made: taken before anything can change who holds them.
  const villageIncome = await collectVillages(userId);
  const market = await collectMarket(userId);
  let villageError = "";
  if (body.action === "recall_guard" || body.action === "abandon_village") {
    villageError = await villageOrder(userId, body);
    body = { action: "state" };
  }
  // Your castle's boost from the capitals your alliance holds.
  const held = await allianceCapitals(userId);
  const boost = capitalBoost(rules, held.levels, held.guilds);
  let village: { target: VillageTarget; row: Row } | null = null;
  if (["attack_village", "station", "build_capital"].includes(String(body.action))) village = await findVillage(body.village, userId);

  let target: { target: Target; row: Row } | null = null;
  if (["attack_player", "spy", "sabotage_player", "send_resources", "send_defenders"].includes(String(body.action))) {
    target = await findTarget(body.target, userId);
  }

  // Buying: take the offer first, so that two buyers can't both have it; it goes back up if you can't pay.
  let bought: { offer: Offer; seller: string } | null = null;
  if (body.action === "buy_offer") {
    const took = await takeOffer(userId, body.id);
    if (typeof took === "string") {
      marketError = took;
      body = { action: "state", market: true };
    } else bought = took;
  }
  let openOffers = 0;
  if (body.action === "post_offer") {
    // Gear and gem offers (for Marks) and resource offers each have their own limit.
    const forMarks = body.give === "gear" || body.want === MARKS || isItemGood(body.give, rules.gear);
    const query = admin.from("market_offers").select("id", { count: "exact", head: true })
      .eq("seller", userId).eq("state", "open").gt("expires", now());
    const { count } = await (forMarks ? query.eq("want", MARKS) : query.neq("want", MARKS));
    openOffers = count ?? 0;
  }

  // Armies back from attacking players; take them so no other request adds them too.
  const { data: back } = await admin.from("raids").select("*").eq("attacker", userId).eq("state", "home").lte("back", now());
  const homecomings: Homecoming[] = [];
  for (const row of back ?? []) {
    const { data: claimed } = await admin.from("raids").update({ state: "done" }).eq("id", row.id).eq("state", "home").select("id");
    if (claimed && claimed.length > 0) homecomings.push(raidFromRow(row));
  }
  // Defenders back from allies, the same way.
  const { data: helpersBack } = await admin.from("aid").select("*").eq("sender", userId).eq("kind", "troops").eq("state", "out")
    .lte("back", now());
  for (const row of helpersBack ?? []) {
    const { data: claimed } = await admin.from("aid").update({ state: "done" }).eq("id", row.id).eq("state", "out").select("id");
    if (claimed && claimed.length > 0) homecomings.push({ back: row.back, survivors: row.army, loot: {} });
  }

  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row, error } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (error) return reply({ ok: false, error: "The server couldn't load your castle." }, 500);
    if (!row) {
      if (founded !== null) await store.remove(founded);
      if (bought !== null) await releaseOffer(userId, bought.offer.id);
      return reply({ ok: false, error: "No castle yet.", needs_join: true });
    }
    const { version, ...stored } = row as PlayerState & { version: number };
    const t = now();
    // A ranked prize goes by your place among the players of that horde.
    let hordePlace = 0;
    if (body.action === "claim_horde_prize" && (stored.horde_points ?? 0) > 0) {
      hordePlace = await hordeRank(Number(stored.horde_key ?? 0), Number(stored.horde_points));
    }
    // Last season's prizes go by your place and your alliance's in its ranking.
    let seasonPlace: { player: number; alliance: number } | undefined;
    if (body.action === "claim_season_prize") {
      const prev = lastSeasonOf(stored, t);
      const me = await store.player(userId);
      seasonPlace = prev && prev.points > 0 ? await seasonPlaces(prev.key, prev.points, me?.alliance_id ?? null) : { player: 0, alliance: 0 };
    }
    // An outpost goes on the free spot nearest your home.
    let outpostSpot: [number, number] | null = null;
    if (body.action === "found_outpost" && !stored.outpost) {
      const taken = await takenSpots();
      if (taken === null) return reply({ ok: false, error: "The server couldn't load the map." }, 500);
      outpostSpot = nearestSpot((world as World).spots, [stored.home_x, stored.home_y], taken);
    }
    const outcome = act(rules, stored, body, t, { pvp, outpostSpot, target: target?.target, homecomings, alliances: allianceRules, aid: aidRules,
      events: { rules: calendar, world: world as World }, quests: questRules, achievements: achievementRules, login: loginRules, seasons: seasonRules, tourney: tourneyRules, seasonPlace, chests: chestRules, encounters, weather,
      sabotage: sabotageRules, targetCastle: target ? (target.row as PlayerState).castle : undefined, village: village?.target, villageIncome,
      capitalBoost: boost, fortresses: (world as World).fortresses, hordeRank: hordePlace,
      market: { rules: marketRules, open: openOffers, offer: bought?.offer }, marketIncome: market.income, marketItems: market.items });
    // Save only if nobody else changed the row meanwhile; otherwise start over.
    const { data: saved, error: saveError } = await admin.from("players")
      .update({ ...outcome.state, ...publicColumns(outcome.state), version: version + 1, updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saveError) {
      if (founded !== null) await store.remove(founded);
      if (bought !== null) await releaseOffer(userId, bought.offer.id);
      return reply({ ok: false, error: "The server couldn't save your castle." }, 500);
    }
    if (!saved || saved.length === 0) continue;
    await saveReports(userId, [...outcome.reports, ...market.reports, ...(outcome.marketReports ?? [])]);
    let result = outcome.result ?? null;
    if (outcome.offer) {
      const o = outcome.offer;
      const { error: offerError } = await admin.from("market_offers").insert({ seller: userId, ...o });
      if (offerError) {
        const refunded = o.want === MARKS ? await refundItem(userId, o) : await refund(userId, { [o.give]: o.give_amount });
        return reply(await view(userId, refunded ?? outcome.state, { error: "The market couldn't take your offer, try again.",
          result: await marketView(userId) }));
      }
    }
    if (bought !== null) {
      if (outcome.error !== "") await releaseOffer(userId, bought.offer.id);
      else {
        const o = bought.offer;
        await admin.from("market_offers").update({ state: "sold", buyer_name: outcome.state.name }).eq("id", o.id).eq("state", "buying");
        await saveReports(bought.seller, [{ kind: "market", event: "sold", at: t, name: outcome.state.name, give: o.give,
          give_amount: o.give_amount, want: o.want, want_amount: o.want_amount, proceeds: o.proceeds,
          ...(o.item ? { item_name: o.item.name } : {}) }]);
      }
    }
    if (MARKET_ORDERS.has(String(body.action)) || body.market === true) result = await marketView(userId);
    if (outcome.raid && village) {
      const r = outcome.raid;
      await admin.from("raids").insert({
        attacker: userId, defender: r.mission === "attack" ? village.row.owner : null, attacker_name: r.attacker_name,
        defender_name: r.defender_name, village: r.village, mission: r.mission,
        army: r.army, waves: r.waves ?? null, tools: r.tools ?? null, lead: r.lead ?? null, from_x: r.from[0], from_y: r.from[1], to_x: r.to[0], to_y: r.to[1],
        depart: r.depart, arrive: r.arrive, back: r.back,
      });
    } else if (outcome.raid && target) {
      const r = outcome.raid;
      await admin.from("raids").insert({
        attacker: userId, defender: target.row.user_id, attacker_name: r.attacker_name, defender_name: r.defender_name,
        army: r.army, waves: r.waves ?? null, tools: r.tools ?? null, lead: r.lead ?? null, from_x: r.from[0], from_y: r.from[1], to_x: r.to[0], to_y: r.to[1],
        depart: r.depart, arrive: r.arrive, back: r.back,
      });
    }
    if (outcome.aid && target) {
      const a = outcome.aid;
      await admin.from("aid").insert({
        sender: userId, receiver: target.row.user_id, sender_name: a.sender_name, receiver_name: a.receiver_name, kind: a.kind,
        resources: a.resources, army: a.army, from_x: a.from[0], from_y: a.from[1], to_x: a.to[0], to_y: a.to[1],
        depart: a.depart, arrive: a.arrive, leave: a.leave, back: a.back,
      });
    }
    // A town building paid for: put it up in the capital, unless the capital changed hands meanwhile.
    if (outcome.capitalBuild && village) {
      const built = await startTownBuilding(userId, village.target.info, outcome.capitalBuild.state, village.row.version);
      if (!built) {
        const refunded = await refund(userId, outcome.capitalBuild.cost);
        return reply(await view(userId, refunded ?? outcome.state, { error: "That capital changed hands meanwhile, try again.", result }));
      }
    }
    if (body.action === "sabotage_player" && outcome.error === "" && target) {
      await agentsArrive(target.row.user_id, userId, stored.name, outcome.state, outcome.result as SentAgents, Number(body.agents), t);
    }
    if (body.action === "spy" && outcome.error === "" && target) {
      const helpers = await helpersAt(target.row.user_id, t);
      result = spyReport(rules, pvp, target.row as PlayerState, t, helpers.map((h) => h.army));
      // Both sides keep a report: the spy's of what they saw, the castle's of who came looking.
      await saveReports(userId, [{ ...result, kind: "spy", role: "spy" }]);
      await saveReports(target.row.user_id, [{ kind: "spy", role: "target", name: stored.name, at: t }]);
    }
    if (founded !== null) {
      if (outcome.error !== "") await store.remove(founded);
      result = await allianceView(store, allianceRules, userId);
    }
    return reply(await view(userId, outcome.state, { error: recalled || villageError || marketError || warError || outcome.error, result }));
  }
  if (founded !== null) await store.remove(founded);
  if (bought !== null) await releaseOffer(userId, bought.offer.id);
  return reply({ ok: false, error: "The server is busy, try again." }, 503);
});
