// Alliances kept in the database (see the alliances migration): the
// AllianceStore index.ts hands to alliances.ts.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { Alliance, AllianceStore, AllianceSummary, Pending, PlayerRef, Role } from "./alliances.ts";

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

const PLAYER = "user_id, name, level, might, alliance_id, alliance_role, alliance_joined";

function ref(r: Row): PlayerRef {
  return {
    user: r.user_id, name: r.name, level: r.level, might: r.might, alliance_id: r.alliance_id === null ? null : Number(r.alliance_id),
    role: r.alliance_role, joined: r.alliance_joined,
  };
}

function alliance(r: Row): Alliance {
  return { id: Number(r.id), name: r.name, tag: r.tag, open: r.open, description: r.description };
}

export class DatabaseAllianceStore implements AllianceStore {
  db: SupabaseClient;

  constructor(db: SupabaseClient) {
    this.db = db;
  }

  async player(user: string) {
    const { data } = await this.db.from("players").select(PLAYER).eq("user_id", user).maybeSingle();
    return data ? ref(data) : null;
  }

  async playerByName(name: string) {
    const { data } = await this.db.from("players").select(PLAYER).ilike("name", name.replace(/[%_\\]/g, "\\$&")).maybeSingle();
    return data ? ref(data) : null;
  }

  async alliance(id: number) {
    const { data } = await this.db.from("alliances").select("id, name, tag, open, description").eq("id", id).maybeSingle();
    return data ? alliance(data) : null;
  }

  async alliances(limit: number): Promise<AllianceSummary[]> {
    const { data } = await this.db.from("alliance_summaries").select("*").order("might", { ascending: false })
      .order("name").limit(limit);
    return (data ?? []).map((r: Row) => ({ ...alliance(r), members: Number(r.members), might: Number(r.might) }));
  }

  async members(id: number) {
    const { data } = await this.db.from("players").select(PLAYER).eq("alliance_id", id);
    return (data ?? []).map(ref);
  }

  async create(a: Omit<Alliance, "id">, leader: string, now: number) {
    const { data, error } = await this.db.from("alliances").insert(a).select("id").single();
    if (error) {
      if (error.code === "23505") return error.message.includes("tag") ? "tag" as const : "name" as const;
      throw new Error(error.message);
    }
    const id = Number(data.id);
    await this.setMember(leader, id, "leader", now);
    return id;
  }

  async remove(id: number) {
    await this.db.from("players").update({ alliance_id: null, alliance_role: null, alliance_joined: 0 }).eq("alliance_id", id);
    await this.db.from("alliances").delete().eq("id", id);
  }

  async update(id: number, fields: Partial<Pick<Alliance, "open" | "description">>) {
    if (Object.keys(fields).length > 0) await this.db.from("alliances").update(fields).eq("id", id);
  }

  async setMember(user: string, id: number | null, role: Role | null, now: number) {
    await this.db.from("players").update({ alliance_id: id, alliance_role: role, alliance_joined: id === null ? 0 : now })
      .eq("user_id", user);
  }

  async pending(filter: { alliance_id?: number; user?: string }): Promise<Pending[]> {
    let q = this.db.from("alliance_pending").select("alliance_id, user_id, kind, at");
    if (filter.alliance_id !== undefined) q = q.eq("alliance_id", filter.alliance_id);
    if (filter.user !== undefined) q = q.eq("user_id", filter.user);
    const { data } = await q.order("at");
    return (data ?? []).map((r: Row) => ({ alliance_id: Number(r.alliance_id), user: r.user_id, kind: r.kind, at: r.at }));
  }

  async addPending(p: Pending) {
    await this.db.from("alliance_pending").upsert({ alliance_id: p.alliance_id, user_id: p.user, kind: p.kind, at: p.at });
  }

  async removePending(filter: { alliance_id?: number; user?: string }) {
    if (filter.alliance_id === undefined && filter.user === undefined) return;
    let q = this.db.from("alliance_pending").delete();
    if (filter.alliance_id !== undefined) q = q.eq("alliance_id", filter.alliance_id);
    if (filter.user !== undefined) q = q.eq("user_id", filter.user);
    await q;
  }
}
