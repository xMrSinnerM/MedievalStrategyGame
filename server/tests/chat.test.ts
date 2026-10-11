// Chat (supabase/functions/game/chat.ts) with the in-memory store.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CHAT_GAP, CHAT_KEPT, CHAT_SHOWN, chatView, checkMessage, cleanMessage, MESSAGE_LENGTH, MemoryChatStore, send, type Speaker,
} from "../../supabase/functions/game/chat.ts";

const T0 = 1_000_000;
const ann: Speaker = { user: "ann", name: "Ann", tag: "OAK", alliance_id: 1 };
const bob: Speaker = { user: "bob", name: "Bob", tag: "OAK", alliance_id: 1 };
const cid: Speaker = { user: "cid", name: "Cid", tag: "", alliance_id: null };
const dan: Speaker = { user: "dan", name: "Dan", tag: "ASH", alliance_id: 2 };

const texts = async (s: MemoryChatStore, who: Speaker, after = 0) =>
  (await chatView(s, who, after)).chat.messages.map((m) => `${m.channel}:${m.name}:${m.text}`);

test("messages are cleaned and checked", () => {
  assert.equal(cleanMessage("  hello\n\tthere  "), "hello there");
  assert.equal(cleanMessage("a\u0000b​c"), "a b c");
  assert.equal(cleanMessage(5), "");
  assert.equal(checkMessage(""), "Write something first.");
  assert.equal(checkMessage("x".repeat(MESSAGE_LENGTH)), "");
  assert.equal(checkMessage("x".repeat(MESSAGE_LENGTH + 1)), `Messages are at most ${MESSAGE_LENGTH} characters long.`);
});

test("world and alliance channels", async () => {
  const s = new MemoryChatStore();
  assert.equal(await send(s, ann, { channel: "world", text: "Hello all" }, T0), "");
  assert.equal(await send(s, bob, { channel: "alliance", text: "Hi Ann" }, T0), "");
  assert.equal(await send(s, dan, { channel: "alliance", text: "Ash only" }, T0), "");
  assert.equal(await send(s, cid, { channel: "alliance", text: "x" }, T0), "You aren't in an alliance.");
  assert.equal(await send(s, cid, { channel: "shout", text: "x" }, T0), "Choose a channel.");
  assert.deepEqual(await texts(s, ann), ["world:Ann:Hello all", "alliance:Bob:Hi Ann"]);
  assert.deepEqual(await texts(s, cid), ["world:Ann:Hello all"]);
  assert.deepEqual(await texts(s, dan), ["world:Ann:Hello all", "alliance:Dan:Ash only"]);
  const view = await chatView(s, ann, 0);
  assert.equal(view.chat.in_alliance, true);
  assert.equal(view.chat.messages[0].tag, "OAK");
  assert.equal((await chatView(s, cid, 0)).chat.in_alliance, false);
  // Only what's newer than the last message you have.
  const last = view.chat.messages[0].id;
  assert.deepEqual(await texts(s, ann, last), ["alliance:Bob:Hi Ann"]);
  assert.deepEqual(await texts(s, ann, -5), await texts(s, ann, 0));
});

test("players must wait between messages", async () => {
  const s = new MemoryChatStore();
  assert.equal(await send(s, ann, { channel: "world", text: "one" }, T0), "");
  assert.equal(await send(s, ann, { channel: "world", text: "two" }, T0 + CHAT_GAP / 2), "Slow down a little.");
  assert.equal(await send(s, bob, { channel: "world", text: "bob" }, T0 + CHAT_GAP / 2), "");
  assert.equal(await send(s, ann, { channel: "world", text: "three" }, T0 + CHAT_GAP), "");
  assert.deepEqual((await texts(s, cid)).map((t) => t.split(":")[2]), ["one", "bob", "three"]);
});

test("only the latest messages are sent, and old ones go", async () => {
  const s = new MemoryChatStore();
  for (let i = 0; i < CHAT_SHOWN + 10; i++) await send(s, ann, { channel: "world", text: `m${i}` }, T0 + i * CHAT_GAP);
  const shown = await texts(s, cid);
  assert.equal(shown.length, CHAT_SHOWN);
  assert.equal(shown[shown.length - 1], `world:Ann:m${CHAT_SHOWN + 9}`);
  await send(s, bob, { channel: "world", text: "much later" }, T0 + CHAT_KEPT + 1000);
  assert.deepEqual(await texts(s, cid), ["world:Bob:much later"]);
});
