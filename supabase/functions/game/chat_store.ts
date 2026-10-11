// Chat kept in the database (see the chat migration): the ChatStore index.ts
// hands to chat.ts.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { Channel, ChatMessage, ChatStore, NewMessage } from "./chat.ts";

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

export class DatabaseChatStore implements ChatStore {
  db: SupabaseClient;

  constructor(db: SupabaseClient) {
    this.db = db;
  }

  async add(m: NewMessage) {
    const { error } = await this.db.from("chat_messages").insert({
      alliance_id: m.alliance_id, user_id: m.user, name: m.name, tag: m.tag, text: m.text, at: m.at,
    });
    if (error) throw new Error(error.message);
  }

  async since(after: number, alliance_id: number | null, limit: number): Promise<ChatMessage[]> {
    let q = this.db.from("chat_messages").select("id, alliance_id, name, tag, text, at").gt("id", after);
    q = alliance_id === null ? q.is("alliance_id", null) : q.or(`alliance_id.is.null,alliance_id.eq.${alliance_id}`);
    const { data } = await q.order("id", { ascending: false }).limit(limit);
    return (data ?? []).reverse().map((r: Row) => ({
      id: Number(r.id), channel: (r.alliance_id === null ? "world" : "alliance") as Channel, name: r.name, tag: r.tag,
      text: r.text, at: r.at,
    }));
  }

  async lastSent(user: string) {
    const { data } = await this.db.from("chat_messages").select("at").eq("user_id", user)
      .order("id", { ascending: false }).limit(1).maybeSingle();
    return data ? Number(data.at) : 0;
  }

  async prune(before: number) {
    await this.db.from("chat_messages").delete().lt("at", before);
  }
}
