// Chat: one world channel everyone online can read, and one channel for each
// alliance. Like alliances.ts, the rules live here and the storage behind a
// ChatStore, so the game server (database) and the local test server
// (memory) share them.
//
// The game asks for messages newer than the last one it has ("after"); the
// first time it gets the latest few. Alliance messages go to whoever is in
// the alliance now, so a new member sees its recent talk and a player who
// leaves stops seeing it.

export type Channel = "world" | "alliance";

export interface ChatMessage {
  id: number;
  channel: Channel;
  name: string;
  tag: string;
  text: string;
  at: number;
}

/** A message to store: alliance_id is null for the world channel. */
export interface NewMessage {
  alliance_id: number | null;
  user: string;
  name: string;
  tag: string;
  text: string;
  at: number;
}

export interface ChatStore {
  add(m: NewMessage): Promise<void>;
  /** The newest `limit` messages after `after` in the world channel and (if not null) this alliance's, oldest first. */
  since(after: number, alliance_id: number | null, limit: number): Promise<ChatMessage[]>;
  /** When this player last sent a message (0 if never). */
  lastSent(user: string): Promise<number>;
  /** Deletes messages sent before `before`. */
  prune(before: number): Promise<void>;
}

export const MESSAGE_LENGTH = 200;
/** Seconds a player must wait between messages. */
export const CHAT_GAP = 2;
/** Messages sent at most this many at a time. */
export const CHAT_SHOWN = 50;
/** How long messages are kept, in seconds. */
export const CHAT_KEPT = 3 * 24 * 3600;

/** A message cleaned up for sending: spaces trimmed, line breaks and control characters gone. */
export function cleanMessage(text: unknown): string {
  if (typeof text !== "string") return "";
  return text.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]+/gu, " ").replace(/\s+/g, " ").trim();
}

export function checkMessage(text: string): string {
  if (text === "") return "Write something first.";
  if ([...text].length > MESSAGE_LENGTH) return `Messages are at most ${MESSAGE_LENGTH} characters long.`;
  return "";
}

/** The player sending or reading: their name, tag and alliance. */
export interface Speaker {
  user: string;
  name: string;
  tag: string;
  alliance_id: number | null;
}

/** Sends a message to the world or your alliance; the error, or "" when sent. */
export async function send(store: ChatStore, who: Speaker, req: Record<string, unknown>, now: number): Promise<string> {
  const channel = req.channel === "alliance" ? "alliance" : req.channel === "world" ? "world" : null;
  if (channel === null) return "Choose a channel.";
  if (channel === "alliance" && who.alliance_id === null) return "You aren't in an alliance.";
  const text = cleanMessage(req.text);
  const why = checkMessage(text);
  if (why !== "") return why;
  if (now - (await store.lastSent(who.user)) < CHAT_GAP) return "Slow down a little.";
  await store.add({
    alliance_id: channel === "alliance" ? who.alliance_id : null, user: who.user, name: who.name, tag: who.tag,
    text: [...text].slice(0, MESSAGE_LENGTH).join(""), at: now,
  });
  await store.prune(now - CHAT_KEPT);
  return "";
}

/** What the chat box shows: the messages after `after` the player can read. */
export async function chatView(store: ChatStore, who: Speaker | null, after: unknown) {
  const from = typeof after === "number" && Number.isFinite(after) && after > 0 ? Math.floor(after) : 0;
  const alliance = who?.alliance_id ?? null;
  return { chat: { messages: await store.since(from, alliance, CHAT_SHOWN), in_alliance: alliance !== null } };
}

/** Chat kept in memory: for the local test server and the tests. */
export class MemoryChatStore implements ChatStore {
  messages: (NewMessage & { id: number })[] = [];
  nextId = 1;

  async add(m: NewMessage) {
    this.messages.push({ ...m, id: this.nextId++ });
  }

  async since(after: number, alliance_id: number | null, limit: number) {
    return this.messages
      .filter((m) => m.id > after && (m.alliance_id === null || m.alliance_id === alliance_id))
      .slice(-limit)
      .map((m) => ({ id: m.id, channel: (m.alliance_id === null ? "world" : "alliance") as Channel, name: m.name, tag: m.tag,
        text: m.text, at: m.at }));
  }

  async lastSent(user: string) {
    let last = 0;
    for (const m of this.messages) if (m.user === user) last = Math.max(last, m.at);
    return last;
  }

  async prune(before: number) {
    this.messages = this.messages.filter((m) => m.at >= before);
  }
}
