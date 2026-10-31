// Mail: letters between players, and the reports inbox (every battle, spy,
// cart and market report the server leaves you). Like chat.ts, the rules live
// here and the storage behind a MailStore, so the game server (database) and
// the local test server (memory) share them.
//
// Every letter is a row in someone's mailbox: sending one puts a copy in the
// sender's "sent" folder and one in each receiver's "inbox", so each side
// reads and deletes their own copy. A letter to your alliance (leaders and
// officers) goes to every other member. Reports are the reports table's rows,
// with a read mark.

export type Folder = "inbox" | "sent" | "reports";

export interface Letter {
  id: number;
  folder: "inbox" | "sent";
  /** Who wrote it, and who it went to (a name, or "[TAG] alliance" for a letter to an alliance). */
  from_name: string;
  to_name: string;
  subject: string;
  text: string;
  at: number;
  read: boolean;
}

export interface ReportRow {
  id: number;
  at: number;
  report: unknown;
  read: boolean;
}

/** A letter to store, in `owner`'s mailbox. */
export type NewLetter = Omit<Letter, "id"> & { owner: string; sender: string };

export interface MailStore {
  add(letters: NewLetter[]): Promise<void>;
  /** The newest `limit` letters in this folder older than `before` (0: from the newest), newest first. */
  letters(owner: string, folder: "inbox" | "sent", before: number, limit: number): Promise<Letter[]>;
  reports(owner: string, before: number, limit: number): Promise<ReportRow[]>;
  /** Marks these letters or reports read (all of them in the folder when `ids` is null). */
  markRead(owner: string, folder: Folder, ids: number[] | null): Promise<void>;
  remove(owner: string, folder: Folder, ids: number[]): Promise<void>;
  unread(owner: string): Promise<{ inbox: number; reports: number }>;
  /** When this player sent their letters since `since` (for the limits). */
  sentSince(sender: string, since: number): Promise<number[]>;
  /** Deletes letters sent before `before`. */
  prune(before: number): Promise<void>;
}

/** The player sending: their account, name, alliance and role in it. */
export interface Writer {
  user: string;
  name: string;
  alliance_id: number | null;
  tag: string;
  role: string | null;
}

/** A player a letter can go to. */
export interface Addressee {
  user: string;
  name: string;
}

/** Looking players up: by name, and the members of an alliance. */
export interface Directory {
  byName(name: string): Promise<Addressee | null>;
  members(alliance_id: number): Promise<Addressee[]>;
}

export const SUBJECT_LENGTH = 60;
export const LETTER_LENGTH = 1000;
export const LETTER_LINES = 30;
/** Seconds a player must wait between letters. */
export const MAIL_GAP = 10;
/** Letters a player may send in an hour (a letter to the alliance counts once). */
export const MAIL_PER_HOUR = 30;
/** Letters and reports shown on one page of a folder. */
export const MAIL_PAGE = 30;
/** How long letters are kept, in seconds. */
export const MAIL_KEPT = 30 * 24 * 3600;
const IDS_AT_ONCE = 100;

/** A subject cleaned up: one line, spaces trimmed. */
export function cleanSubject(text: unknown): string {
  if (typeof text !== "string") return "";
  const one = text.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]+/gu, " ").replace(/\s+/g, " ").trim();
  return [...one].slice(0, SUBJECT_LENGTH).join("");
}

/** A letter's text cleaned up: line breaks kept (at most one empty line in a row), other control characters gone. */
export function cleanLetter(text: unknown): string {
  if (typeof text !== "string") return "";
  return text.replace(/\r\n?/g, "\n").replace(/[\p{Zl}\p{Zp}]/gu, "\n")
    .replace(/[^\S\n]+/gu, " ").replace(/[\p{Cc}\p{Cf}]/gu, (c) => (c === "\n" ? c : ""))
    .split("\n").map((l) => l.trim()).join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

export function checkLetter(text: string): string {
  if (text === "") return "Write something first.";
  if ([...text].length > LETTER_LENGTH) return `Letters are at most ${LETTER_LENGTH} characters long.`;
  if (text.split("\n").length > LETTER_LINES) return `Letters are at most ${LETTER_LINES} lines long.`;
  return "";
}

function folderOf(value: unknown): Folder | null {
  return value === "inbox" || value === "sent" || value === "reports" ? value : null;
}

function idsOf(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v) => typeof v === "number" && Number.isInteger(v) && v > 0).slice(0, IDS_AT_ONCE);
}

/** Sends a letter to a player (`to`, a name) or, with `alliance: true`, to your alliance; the error, or "" when sent. */
export async function sendLetter(store: MailStore, dir: Directory, who: Writer, req: Record<string, unknown>,
  now: number): Promise<string> {
  const text = cleanLetter(req.text);
  const why = checkLetter(text);
  const subject = cleanSubject(req.subject) || "(no subject)";
  let to: Addressee[];
  let toName: string;
  if (req.alliance === true) {
    if (who.alliance_id === null) return "You aren't in an alliance.";
    if (who.role !== "leader" && who.role !== "officer") return "Only the leader and officers write to the whole alliance.";
    to = (await dir.members(who.alliance_id)).filter((m) => m.user !== who.user);
    if (to.length === 0) return "Nobody else is in your alliance yet.";
    toName = `[${who.tag}] alliance`;
  } else {
    if (typeof req.to !== "string" || req.to.trim() === "") return "Who is it for?";
    const found = await dir.byName(req.to.trim());
    if (found === null) return "There's no player by that name.";
    if (found.user === who.user) return "You can't write to yourself.";
    to = [found];
    toName = found.name;
  }
  if (why !== "") return why;
  const sent = await store.sentSince(who.user, now - 3600);
  if (sent.some((at) => now - at < MAIL_GAP)) return "Wait a few seconds before the next letter.";
  if (sent.length >= MAIL_PER_HOUR) return `You can send ${MAIL_PER_HOUR} letters an hour. Try again later.`;
  const letter = { from_name: who.name, to_name: toName, subject, text, at: now, sender: who.user };
  await store.add([
    { ...letter, owner: who.user, folder: "sent", read: true },
    ...to.map((m) => ({ ...letter, owner: m.user, folder: "inbox" as const, read: false })),
  ]);
  await store.prune(now - MAIL_KEPT);
  return "";
}

/** Marking read, deleting: the error, or "". */
export async function mailOrder(store: MailStore, owner: string, req: Record<string, unknown>): Promise<string> {
  const folder = folderOf(req.folder);
  if (folder === null) return "Choose a folder.";
  if (req.action === "mail_read_all") {
    await store.markRead(owner, folder, null);
    return "";
  }
  const ids = idsOf(req.ids);
  if (ids.length === 0) return "";
  if (req.action === "mail_read") await store.markRead(owner, folder, ids);
  else if (req.action === "mail_delete") await store.remove(owner, folder, ids);
  return "";
}

/** One page of a folder (`before`: the last id of the page before), with how many letters and reports are unread. */
export async function mailView(store: MailStore, owner: string, req: Record<string, unknown>) {
  const folder = folderOf(req.folder) ?? "inbox";
  const before = typeof req.before === "number" && Number.isFinite(req.before) && req.before > 0 ? Math.floor(req.before) : 0;
  const items = folder === "reports"
    ? await store.reports(owner, before, MAIL_PAGE + 1)
    : await store.letters(owner, folder, before, MAIL_PAGE + 1);
  return {
    mail: {
      folder, before, items: items.slice(0, MAIL_PAGE), more: items.length > MAIL_PAGE,
      unread: await store.unread(owner),
    },
  };
}

export const MAIL_ORDERS = new Set(["mail", "mail_send", "mail_read", "mail_read_all", "mail_delete"]);

/** Mail kept in memory: for the local test server and the tests. `reports` is the server's own list of reports. */
export class MemoryMailStore implements MailStore {
  rows: (NewLetter & { id: number })[] = [];
  nextId = 1;
  reportRows: { id: number; user: string; at: number; report: unknown; read?: boolean }[];

  constructor(reports: { id: number; user: string; at: number; report: unknown; read?: boolean }[] = []) {
    this.reportRows = reports;
  }

  async add(letters: NewLetter[]) {
    for (const l of letters) this.rows.push({ ...l, id: this.nextId++ });
  }

  async letters(owner: string, folder: "inbox" | "sent", before: number, limit: number) {
    return this.rows.filter((r) => r.owner === owner && r.folder === folder && (before === 0 || r.id < before))
      .sort((a, b) => b.id - a.id).slice(0, limit)
      .map(({ owner: _o, sender: _s, ...l }) => ({ ...l }));
  }

  async reports(owner: string, before: number, limit: number) {
    return this.reportRows.filter((r) => r.user === owner && (before === 0 || r.id < before))
      .sort((a, b) => b.id - a.id).slice(0, limit)
      .map((r) => ({ id: r.id, at: r.at, report: r.report, read: r.read === true }));
  }

  async markRead(owner: string, folder: Folder, ids: number[] | null) {
    const hit = (id: number) => ids === null || ids.includes(id);
    if (folder === "reports") {
      for (const r of this.reportRows) if (r.user === owner && hit(r.id)) r.read = true;
    } else {
      for (const r of this.rows) if (r.owner === owner && r.folder === folder && hit(r.id)) r.read = true;
    }
  }

  async remove(owner: string, folder: Folder, ids: number[]) {
    if (folder === "reports") {
      for (let i = this.reportRows.length - 1; i >= 0; i--) {
        const r = this.reportRows[i];
        if (r.user === owner && ids.includes(r.id)) this.reportRows.splice(i, 1);
      }
    } else {
      this.rows = this.rows.filter((r) => !(r.owner === owner && r.folder === folder && ids.includes(r.id)));
    }
  }

  async unread(owner: string) {
    return {
      inbox: this.rows.filter((r) => r.owner === owner && r.folder === "inbox" && !r.read).length,
      reports: this.reportRows.filter((r) => r.user === owner && r.read !== true).length,
    };
  }

  async sentSince(sender: string, since: number) {
    return this.rows.filter((r) => r.owner === sender && r.folder === "sent" && r.at >= since).map((r) => r.at);
  }

  async prune(before: number) {
    this.rows = this.rows.filter((r) => r.at >= before);
  }
}
