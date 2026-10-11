// Alliances: found one, invite players or let them ask to join, give out
// roles, leave, and the alliance screen's view of it all. The rules live
// here and the storage behind an AllianceStore, so the game server
// (index.ts, the database) and the local test server (memory) share them.
//
// Roles: the leader can do everything; officers invite players, answer
// requests to join and remove members; members just belong. Founding costs
// gold, which comes out of the castle through act() ("found_alliance").

import type { Dict } from "../../../server/rules/util.ts";

/** The numbers for alliances, from data/alliances.json. */
export interface AllianceRules {
  found_cost: Dict;
  found_keep: number;
  max_members: number;
}

export type Role = "leader" | "officer" | "member";

export interface Alliance {
  id: number;
  name: string;
  tag: string;
  open: boolean;
  description: string;
}

/** An alliance in the list of all alliances. */
export interface AllianceSummary extends Alliance {
  members: number;
  might: number;
}

/** A player as alliances see them. */
export interface PlayerRef {
  user: string;
  name: string;
  alliance_id: number | null;
  role: Role | null;
  level: number;
  might: number;
  joined: number;
}

/** An invitation to a player, or a player's request to join. */
export interface Pending {
  alliance_id: number;
  user: string;
  kind: "invite" | "request";
  at: number;
}

export interface AllianceStore {
  player(user: string): Promise<PlayerRef | null>;
  playerByName(name: string): Promise<PlayerRef | null>;
  alliance(id: number): Promise<Alliance | null>;
  /** The mightiest alliances first. */
  alliances(limit: number): Promise<AllianceSummary[]>;
  members(id: number): Promise<PlayerRef[]>;
  /** A new alliance led by `leader`; "name" or "tag" if one is taken already. */
  create(a: Omit<Alliance, "id">, leader: string, now: number): Promise<number | "name" | "tag">;
  /** Disbands an alliance: its members leave and its invitations go. */
  remove(id: number): Promise<void>;
  update(id: number, fields: Partial<Pick<Alliance, "open" | "description">>): Promise<void>;
  setMember(user: string, id: number | null, role: Role | null, now: number): Promise<void>;
  pending(filter: { alliance_id?: number; user?: string }): Promise<Pending[]>;
  /** Adds an invitation or request, replacing any between the same two. */
  addPending(p: Pending): Promise<void>;
  removePending(filter: { alliance_id?: number; user?: string }): Promise<void>;
}

export const ALLIANCE_NAME_RULE = /^[\p{L}\p{N}][\p{L}\p{N} _'-]{1,22}[\p{L}\p{N}]$/u;
export const TAG_RULE = /^[\p{L}\p{N}]{2,4}$/u;
const LIST_SHOWN = 50;
const DESCRIPTION_LENGTH = 300;
const ROLES: Role[] = ["leader", "officer", "member"];

export function checkAllianceName(name: unknown, tag: unknown): string {
  if (typeof name !== "string" || typeof tag !== "string") return "Choose a name and a tag.";
  const n = name.trim();
  if (n.length < 3 || n.length > 24) return "Alliance names are 3 to 24 characters long.";
  if (!ALLIANCE_NAME_RULE.test(n)) return "Use letters, numbers, spaces, ' _ and - only.";
  if (!TAG_RULE.test(tag.trim())) return "Tags are 2 to 4 letters or numbers.";
  return "";
}

/** Why this player can't found an alliance now, before paying ("" if they can). */
export async function checkFound(store: AllianceStore, user: string, req: Record<string, unknown>): Promise<string> {
  const why = checkAllianceName(req.name, req.tag);
  if (why !== "") return why;
  const me = await store.player(user);
  if (me === null) return "No castle yet.";
  if (me.alliance_id !== null) return "Leave your alliance first.";
  return "";
}

/** Creates the alliance an order asks for (after checkFound); its id, or why not. */
export async function found(store: AllianceStore, user: string, req: Record<string, unknown>, now: number): Promise<number | string> {
  const made = await store.create({
    name: String(req.name).trim(), tag: String(req.tag).trim().toUpperCase(), open: true, description: "",
  }, user, now);
  if (made === "name") return "That alliance name is taken.";
  if (made === "tag") return "That tag is taken.";
  await store.removePending({ user });
  return made;
}

/** Carries out an alliance order; the error, or "" when done. */
export async function handle(store: AllianceStore, rules: AllianceRules, user: string, req: Record<string, unknown>,
  now: number): Promise<string> {
  const me = await store.player(user);
  if (me === null) return "No castle yet.";
  const id = Number(req.id);
  switch (req.action) {
    case "alliance":
      return "";
    case "join_alliance": {
      if (me.alliance_id !== null) return "Leave your alliance first.";
      const a = Number.isInteger(id) ? await store.alliance(id) : null;
      if (a === null) return "There's no such alliance.";
      const invited = (await store.pending({ alliance_id: id, user })).some((p) => p.kind === "invite");
      if (!a.open && !invited) {
        await store.addPending({ alliance_id: id, user, kind: "request", at: now });
        return "";
      }
      return await join(store, rules, user, id, now);
    }
    case "accept_invite": {
      if (me.alliance_id !== null) return "Leave your alliance first.";
      const invited = (await store.pending({ alliance_id: id, user })).some((p) => p.kind === "invite");
      if (!invited || (await store.alliance(id)) === null) return "That invitation is gone.";
      return await join(store, rules, user, id, now);
    }
    case "decline_invite":
    case "cancel_request":
      if (Number.isInteger(id)) await store.removePending({ alliance_id: id, user });
      return "";
    case "leave_alliance":
      if (me.alliance_id === null) return "You aren't in an alliance.";
      return await leave(store, me, now);
  }
  // The rest are for officers and the leader of an alliance.
  if (me.alliance_id === null) return "You aren't in an alliance.";
  const mine = me.alliance_id;
  if (me.role === "member") return "Only the leader and officers can do that.";
  const leader = me.role === "leader";
  switch (req.action) {
    case "invite": {
      const other = await target(store, req.target);
      if (other === null) return "There's no player by that name.";
      if (other.alliance_id === mine) return `${other.name} is in your alliance already.`;
      if (other.alliance_id !== null) return `${other.name} is in another alliance.`;
      const asked = (await store.pending({ alliance_id: mine, user: other.user })).some((p) => p.kind === "request");
      if (asked) return await join(store, rules, other.user, mine, now);
      await store.addPending({ alliance_id: mine, user: other.user, kind: "invite", at: now });
      return "";
    }
    case "cancel_invite": {
      const other = await target(store, req.target);
      if (other !== null) await store.removePending({ alliance_id: mine, user: other.user });
      return "";
    }
    case "answer_request": {
      const other = await target(store, req.target);
      const asked = other !== null && (await store.pending({ alliance_id: mine, user: other.user })).some((p) => p.kind === "request");
      if (other === null || !asked) return "That request is gone.";
      if (req.accept !== true) {
        await store.removePending({ alliance_id: mine, user: other.user });
        return "";
      }
      if (other.alliance_id !== null) {
        await store.removePending({ alliance_id: mine, user: other.user });
        return `${other.name} has joined another alliance.`;
      }
      return await join(store, rules, other.user, mine, now);
    }
    case "kick": {
      const other = await target(store, req.target);
      if (other === null || other.alliance_id !== mine) return "There's no such member.";
      if (other.user === user) return "Leave the alliance instead.";
      if (!leader && other.role !== "member") return "Officers can only remove members.";
      await store.setMember(other.user, null, null, now);
      return "";
    }
    case "set_role": {
      if (!leader) return "Only the leader can change roles.";
      const role = String(req.role) as Role;
      if (!ROLES.includes(role)) return "Unknown role.";
      const other = await target(store, req.target);
      if (other === null || other.alliance_id !== mine) return "There's no such member.";
      if (other.user === user) return "Make someone else leader instead.";
      // Making someone leader hands over the alliance; the old leader becomes an officer.
      if (role === "leader") await store.setMember(user, mine, "officer", me.joined);
      await store.setMember(other.user, mine, role, other.joined);
      return "";
    }
    case "alliance_settings": {
      if (!leader) return "Only the leader can change the alliance's settings.";
      const fields: Partial<Pick<Alliance, "open" | "description">> = {};
      if (typeof req.open === "boolean") fields.open = req.open;
      if (typeof req.description === "string") fields.description = req.description.trim().slice(0, DESCRIPTION_LENGTH);
      await store.update(mine, fields);
      return "";
    }
    case "disband_alliance":
      if (!leader) return "Only the leader can disband the alliance.";
      await store.remove(mine);
      return "";
  }
  return "Unknown order.";
}

async function target(store: AllianceStore, name: unknown): Promise<PlayerRef | null> {
  return typeof name === "string" && name.trim() !== "" ? await store.playerByName(name.trim()) : null;
}

async function join(store: AllianceStore, rules: AllianceRules, user: string, id: number, now: number): Promise<string> {
  if ((await store.members(id)).length >= rules.max_members) return "That alliance is full.";
  await store.setMember(user, id, "member", now);
  await store.removePending({ user });
  return "";
}

async function leave(store: AllianceStore, me: PlayerRef, now: number): Promise<string> {
  const id = me.alliance_id!;
  const others = (await store.members(id)).filter((m) => m.user !== me.user);
  if (others.length === 0) {
    await store.remove(id);
    return "";
  }
  await store.setMember(me.user, null, null, now);
  if (me.role === "leader") {
    // The longest-serving officer takes over, or else the longest-serving member.
    others.sort((a, b) => (a.role === "officer" ? 0 : 1) - (b.role === "officer" ? 0 : 1) || a.joined - b.joined);
    await store.setMember(others[0].user, id, "leader", others[0].joined);
  }
  return "";
}

/** What the alliance screen shows this player. */
export async function allianceView(store: AllianceStore, rules: AllianceRules, user: string) {
  const me = await store.player(user);
  const list = await store.alliances(LIST_SHOWN);
  const base = { rules, alliances: list, you: me?.name ?? "" };
  if (me === null) return { ...base, alliance: null, members: [], requests: [], invited: [], invites: [], asked: [] };
  if (me.alliance_id === null) {
    const mine = await store.pending({ user });
    const named = async (p: Pending) => {
      const a = list.find((x) => x.id === p.alliance_id) ?? await store.alliance(p.alliance_id);
      return a === null ? null : { id: a.id, name: a.name, tag: a.tag, at: p.at };
    };
    const invites = (await Promise.all(mine.filter((p) => p.kind === "invite").map(named))).filter((x) => x !== null);
    const asked = (await Promise.all(mine.filter((p) => p.kind === "request").map(named))).filter((x) => x !== null);
    return { ...base, alliance: null, members: [], requests: [], invited: [], invites, asked };
  }
  const a = await store.alliance(me.alliance_id);
  const members = (await store.members(me.alliance_id))
    .sort((x, y) => ROLES.indexOf(x.role!) - ROLES.indexOf(y.role!) || y.might - x.might)
    .map((m) => ({ name: m.name, role: m.role, level: m.level, might: m.might }));
  let requests: { name: string; at: number }[] = [];
  let invited: { name: string; at: number }[] = [];
  if (me.role !== "member") {
    const pending = await store.pending({ alliance_id: me.alliance_id });
    const name = async (p: Pending) => ({ name: (await store.player(p.user))?.name ?? "?", at: p.at });
    requests = await Promise.all(pending.filter((p) => p.kind === "request").map(name));
    invited = await Promise.all(pending.filter((p) => p.kind === "invite").map(name));
  }
  return { ...base, alliance: a === null ? null : { ...a, role: me.role }, members, requests, invited, invites: [], asked: [] };
}

/** An alliance store kept in memory: for the local test server and the tests. */
export class MemoryAllianceStore implements AllianceStore {
  alliancesById = new Map<number, Alliance>();
  pendingList: Pending[] = [];
  nextId = 1;
  /** Membership by user: the players themselves live in `players`. */
  membership = new Map<string, { alliance_id: number; role: Role; joined: number }>();

  players: () => Map<string, { name: string; level: number; might: number }>;

  /** `players` gives each player's name, keep level and might by user id. */
  constructor(players: () => Map<string, { name: string; level: number; might: number }>) {
    this.players = players;
  }

  ref(user: string): PlayerRef | null {
    const p = this.players().get(user);
    if (p === undefined) return null;
    const m = this.membership.get(user);
    return { user, name: p.name, level: p.level, might: p.might, alliance_id: m?.alliance_id ?? null,
      role: m?.role ?? null, joined: m?.joined ?? 0 };
  }

  async player(user: string) {
    return this.ref(user);
  }

  async playerByName(name: string) {
    for (const [user, p] of this.players()) if (p.name.toLowerCase() === name.toLowerCase()) return this.ref(user);
    return null;
  }

  async alliance(id: number) {
    return this.alliancesById.get(id) ?? null;
  }

  async alliances(limit: number) {
    return [...this.alliancesById.values()].map((a) => {
      const ms = [...this.membership.entries()].filter(([, m]) => m.alliance_id === a.id).map(([u]) => this.ref(u)!);
      return { ...a, members: ms.length, might: ms.reduce((s, m) => s + m.might, 0) };
    }).sort((x, y) => y.might - x.might || x.name.localeCompare(y.name)).slice(0, limit);
  }

  async members(id: number) {
    return [...this.membership.entries()].filter(([, m]) => m.alliance_id === id).map(([u]) => this.ref(u)!);
  }

  async create(a: Omit<Alliance, "id">, leader: string, now: number) {
    for (const x of this.alliancesById.values()) {
      if (x.name.toLowerCase() === a.name.toLowerCase()) return "name" as const;
      if (x.tag.toLowerCase() === a.tag.toLowerCase()) return "tag" as const;
    }
    const id = this.nextId++;
    this.alliancesById.set(id, { ...a, id });
    this.membership.set(leader, { alliance_id: id, role: "leader", joined: now });
    return id;
  }

  async remove(id: number) {
    this.alliancesById.delete(id);
    for (const [u, m] of [...this.membership]) if (m.alliance_id === id) this.membership.delete(u);
    this.pendingList = this.pendingList.filter((p) => p.alliance_id !== id);
  }

  async update(id: number, fields: Partial<Pick<Alliance, "open" | "description">>) {
    const a = this.alliancesById.get(id);
    if (a !== undefined) Object.assign(a, fields);
  }

  async setMember(user: string, id: number | null, role: Role | null, now: number) {
    if (id === null || role === null) this.membership.delete(user);
    else this.membership.set(user, { alliance_id: id, role, joined: now });
  }

  async pending(filter: { alliance_id?: number; user?: string }) {
    return this.pendingList.filter((p) => (filter.alliance_id === undefined || p.alliance_id === filter.alliance_id)
      && (filter.user === undefined || p.user === filter.user));
  }

  async addPending(p: Pending) {
    await this.removePending({ alliance_id: p.alliance_id, user: p.user });
    this.pendingList.push(p);
  }

  async removePending(filter: { alliance_id?: number; user?: string }) {
    const drop = await this.pending(filter);
    this.pendingList = this.pendingList.filter((p) => !drop.includes(p));
  }
}
