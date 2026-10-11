// A stand-in for the Supabase project, for trying the online game without
// the internet: the same sign-up/sign-in endpoints as Supabase Auth and the
// same game function (game.ts), keeping players in memory. Accounts are
// confirmed at once and nothing is saved when it stops.
//
//   node server/dev/local_server.ts            (listens on port 54321)
//   START_TROOPS='{"spearman":60}' node server/dev/local_server.ts   (castles start with soldiers)
//   godot --path . -- --online-url=http://127.0.0.1:54321

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, checkName, newPlayer, type PlayerState, type World } from "../../supabase/functions/game/game.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const PORT = Number(process.env.PORT ?? 54321);
const TOKEN_LIFE = Number(process.env.TOKEN_LIFE ?? 3600);
// For testing: soldiers every new castle starts with, as JSON ({"spearman": 50}).
const START_TROOPS = JSON.parse(process.env.START_TROOPS ?? "{}");

const users = new Map<string, { id: string; password: string }>();
const tokens = new Map<string, { user: string; expires: number }>();
const refreshTokens = new Map<string, string>();
const players = new Map<string, PlayerState>();
const reports: { id: number; user: string; at: number; report: unknown }[] = [];
let nextReport = 1;

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
  return { ok: true, now: now(), ...extra, player: state, reports: mine };
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
      const state = newPlayer(rules, world, String(body.name), now());
      state.castle.troops = { ...START_TROOPS };
      players.set(user, state);
      return send(res, 200, view(user, state));
    }
    const stored = players.get(user);
    if (stored === undefined) return send(res, 200, { ok: false, error: "No castle yet.", needs_join: true });
    const outcome = act(rules, stored, body, now());
    players.set(user, outcome.state);
    for (const r of outcome.reports) reports.push({ id: nextReport++, user, at: r.at, report: r });
    return send(res, 200, view(user, outcome.state, { error: outcome.error, result: outcome.result ?? null }));
  }
  send(res, 404, { msg: "Not found" });
}).listen(PORT, "127.0.0.1", () => console.log(`Local game server on http://127.0.0.1:${PORT}`));
