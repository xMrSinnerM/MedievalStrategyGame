// Mail kept in the database (see the mail migration): the MailStore index.ts
// hands to mail.ts. Reports are the reports table's rows.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { Folder, Letter, MailStore, NewLetter, ReportRow } from "./mail.ts";

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

const LETTER = "id, folder, from_name, to_name, subject, text, at, read";

export class DatabaseMailStore implements MailStore {
  db: SupabaseClient;

  constructor(db: SupabaseClient) {
    this.db = db;
  }

  async add(letters: NewLetter[]) {
    const { error } = await this.db.from("mail").insert(letters.map((l) => ({
      owner: l.owner, sender: l.sender, folder: l.folder, from_name: l.from_name, to_name: l.to_name, subject: l.subject,
      text: l.text, at: l.at, read: l.read,
    })));
    if (error) throw new Error(error.message);
  }

  async letters(owner: string, folder: "inbox" | "sent", before: number, limit: number): Promise<Letter[]> {
    let q = this.db.from("mail").select(LETTER).eq("owner", owner).eq("folder", folder);
    if (before > 0) q = q.lt("id", before);
    const { data } = await q.order("id", { ascending: false }).limit(limit);
    return (data ?? []).map((r: Row) => ({ ...r, id: Number(r.id) }) as Letter);
  }

  async reports(owner: string, before: number, limit: number): Promise<ReportRow[]> {
    let q = this.db.from("reports").select("id, at, report, read").eq("user_id", owner);
    if (before > 0) q = q.lt("id", before);
    const { data } = await q.order("id", { ascending: false }).limit(limit);
    return (data ?? []).map((r: Row) => ({ id: Number(r.id), at: r.at, report: r.report, read: r.read === true }));
  }

  async markRead(owner: string, folder: Folder, ids: number[] | null) {
    let q = folder === "reports"
      ? this.db.from("reports").update({ read: true }).eq("user_id", owner).eq("read", false)
      : this.db.from("mail").update({ read: true }).eq("owner", owner).eq("folder", folder).eq("read", false);
    if (ids !== null) q = q.in("id", ids);
    await q;
  }

  async remove(owner: string, folder: Folder, ids: number[]) {
    if (folder === "reports") await this.db.from("reports").delete().eq("user_id", owner).in("id", ids);
    else await this.db.from("mail").delete().eq("owner", owner).eq("folder", folder).in("id", ids);
  }

  async unread(owner: string) {
    const [inbox, reports] = await Promise.all([
      this.db.from("mail").select("id", { count: "exact", head: true }).eq("owner", owner).eq("folder", "inbox").eq("read", false),
      this.db.from("reports").select("id", { count: "exact", head: true }).eq("user_id", owner).eq("read", false),
    ]);
    return { inbox: inbox.count ?? 0, reports: reports.count ?? 0 };
  }

  async sentSince(sender: string, since: number) {
    const { data } = await this.db.from("mail").select("at").eq("owner", sender).eq("folder", "sent").gte("at", since)
      .limit(1000);
    return (data ?? []).map((r: Row) => Number(r.at));
  }

  async prune(before: number) {
    await this.db.from("mail").delete().lt("at", before);
  }
}
