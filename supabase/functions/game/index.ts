// The game server: one Edge Function that every online order goes through.
// The caller must be signed in (Supabase Auth). It loads their player row,
// runs their world up to the server's clock, carries out the order and saves
// the result, so the game never decides anything itself.
//
// POST { "action": "join", "name": "..." }       create your castle
// POST { "action": "state" }                     your castle, camps, marches and reports
// POST { "action": "place", "type", "cell": [x, y] }
// POST { "action": "upgrade" | "cancel", "id" }
// POST { "action": "move", "id", "cell": [x, y] }
// POST { "action": "recruit", "unit", "amount" }
// POST { "action": "cancel_training", "index" }
// POST { "action": "attack", "camp", "army": { unit: count } }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import buildings from "../../../data/buildings.json" with { type: "json" };
import units from "../../../data/units.json" with { type: "json" };
import barons from "../../../data/barons.json" with { type: "json" };
import world from "../../../server/world/world.json" with { type: "json" };
import { makeRules } from "../../../server/rules/load.ts";
import { act, checkName, newPlayer, type PlayerState, type World } from "./game.ts";

const rules = makeRules(buildings, units, barons);
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const COLUMNS = "name, home_x, home_y, castle, camps, marches, next_march, version";
const REPORTS_SHOWN = 20;
const RETRIES = 4;

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function now(): number {
  return Date.now() / 1000;
}

async function recentReports(userId: string) {
  const { data } = await admin.from("reports").select("id, at, report").eq("user_id", userId)
    .order("id", { ascending: false }).limit(REPORTS_SHOWN);
  return data ?? [];
}

async function view(userId: string, state: PlayerState, extra: Record<string, unknown> = {}) {
  return { ok: true, now: now(), ...extra, player: state, reports: await recentReports(userId) };
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
    const state = newPlayer(rules, world as World, String(body.name), now());
    const { error } = await admin.from("players").insert({ user_id: userId, ...state, version: 1 });
    if (error) {
      if (error.code === "23505") {
        const taken = error.message.includes("name");
        return reply({ ok: false, error: taken ? "That name is taken." : "You already have a castle." });
      }
      return reply({ ok: false, error: "The server couldn't create your castle." }, 500);
    }
    return reply(await view(userId, state));
  }

  for (let attempt = 0; attempt < RETRIES; attempt++) {
    const { data: row, error } = await admin.from("players").select(COLUMNS).eq("user_id", userId).maybeSingle();
    if (error) return reply({ ok: false, error: "The server couldn't load your castle." }, 500);
    if (!row) return reply({ ok: false, error: "No castle yet.", needs_join: true });
    const { version, ...stored } = row as PlayerState & { version: number };
    const outcome = act(rules, stored, body, now());
    // Save only if nobody else changed the row meanwhile; otherwise start over.
    const { data: saved, error: saveError } = await admin.from("players")
      .update({ ...outcome.state, version: version + 1, updated_at: new Date().toISOString() })
      .eq("user_id", userId).eq("version", version).select("version");
    if (saveError) return reply({ ok: false, error: "The server couldn't save your castle." }, 500);
    if (!saved || saved.length === 0) continue;
    if (outcome.reports.length > 0) {
      await admin.from("reports").insert(outcome.reports.map((r) => ({ user_id: userId, at: r.at, report: r })));
    }
    return reply(await view(userId, outcome.state, { error: outcome.error, result: outcome.result ?? null }));
  }
  return reply({ ok: false, error: "The server is busy, try again." }, 503);
});
