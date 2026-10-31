// Mail and the reports inbox (supabase/functions/game/mail.ts) with the in-memory store.
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  checkLetter, cleanLetter, cleanSubject, type Directory, LETTER_LENGTH, MAIL_GAP, MAIL_KEPT, MAIL_PAGE, MAIL_PER_HOUR,
  mailOrder, mailView, MemoryMailStore, sendLetter, type Writer,
} from "../../supabase/functions/game/mail.ts";

const T0 = 1_000_000;
const ann: Writer = { user: "ann", name: "Ann", alliance_id: 1, tag: "OAK", role: "leader" };
const bob: Writer = { user: "bob", name: "Bob", alliance_id: 1, tag: "OAK", role: "member" };
const cid: Writer = { user: "cid", name: "Cid", alliance_id: null, tag: "", role: null };
const everyone = [ann, bob, cid, { user: "dan", name: "Dan", alliance_id: 1, tag: "OAK", role: "officer" }];
const dir: Directory = {
  byName: async (name) => everyone.find((p) => p.name.toLowerCase() === name.toLowerCase()) ?? null,
  members: async (id) => everyone.filter((p) => p.alliance_id === id),
};

const page = async (s: MemoryMailStore, who: string, folder: string, before = 0) =>
  (await mailView(s, who, { folder, before })).mail;

test("letters are cleaned and checked", () => {
  assert.equal(cleanSubject("  Peace\n offer  "), "Peace offer");
  assert.equal(cleanSubject("x".repeat(100)).length, 60);
  assert.equal(cleanLetter("  Hello\r\n\r\n\r\n\r\nthere\t friend \u0000 "), "Hello\n\nthere friend");
  assert.equal(cleanLetter(7), "");
  assert.equal(checkLetter(""), "Write something first.");
  assert.equal(checkLetter("x".repeat(LETTER_LENGTH)), "");
  assert.equal(checkLetter("x".repeat(LETTER_LENGTH + 1)), `Letters are at most ${LETTER_LENGTH} characters long.`);
  assert.match(checkLetter(Array(31).fill("a").join("\n")), /lines/);
});

test("a letter lands in the inbox and the sent folder", async () => {
  const s = new MemoryMailStore();
  assert.equal(await sendLetter(s, dir, ann, { to: "cid", subject: "Hello", text: "Join us?" }, T0), "");
  const inbox = await page(s, "cid", "inbox");
  assert.equal(inbox.items.length, 1);
  assert.deepEqual({ ...inbox.items[0], id: 0 }, { id: 0, folder: "inbox", from_name: "Ann", to_name: "Cid", subject: "Hello",
    text: "Join us?", at: T0, read: false });
  assert.deepEqual(inbox.unread, { inbox: 1, reports: 0 });
  const sent = await page(s, "ann", "sent");
  assert.equal(sent.items.length, 1);
  assert.equal(sent.items[0].read, true);
  assert.equal((await page(s, "ann", "inbox")).items.length, 0);
  assert.equal((await page(s, "bob", "inbox")).items.length, 0);
  // No subject is fine.
  assert.equal(await sendLetter(s, dir, cid, { to: "Ann", text: "Maybe" }, T0 + 60), "");
  assert.equal((await page(s, "ann", "inbox")).items[0].subject, "(no subject)");
});

test("who a letter can go to", async () => {
  const s = new MemoryMailStore();
  assert.equal(await sendLetter(s, dir, ann, { to: "Nobody", text: "x" }, T0), "There's no player by that name.");
  assert.equal(await sendLetter(s, dir, ann, { to: "ann", text: "x" }, T0), "You can't write to yourself.");
  assert.equal(await sendLetter(s, dir, ann, { to: " ", text: "x" }, T0), "Who is it for?");
  assert.equal(await sendLetter(s, dir, ann, { to: "Bob", text: "  " }, T0), "Write something first.");
  assert.equal(s.rows.length, 0);
});

test("leaders and officers write to the whole alliance", async () => {
  const s = new MemoryMailStore();
  assert.equal(await sendLetter(s, dir, bob, { alliance: true, text: "Hi all" }, T0), "Only the leader and officers write to the whole alliance.");
  assert.equal(await sendLetter(s, dir, cid, { alliance: true, text: "Hi all" }, T0), "You aren't in an alliance.");
  assert.equal(await sendLetter(s, dir, ann, { alliance: true, subject: "Muster", text: "Attack at dawn" }, T0), "");
  assert.equal((await page(s, "bob", "inbox")).items[0].to_name, "[OAK] alliance");
  assert.equal((await page(s, "dan", "inbox")).items.length, 1);
  assert.equal((await page(s, "ann", "inbox")).items.length, 0);
  assert.equal((await page(s, "cid", "inbox")).items.length, 0);
  assert.equal((await page(s, "ann", "sent")).items.length, 1);
});

test("letters are spaced out and limited per hour", async () => {
  const s = new MemoryMailStore();
  assert.equal(await sendLetter(s, dir, ann, { to: "Bob", text: "1" }, T0), "");
  assert.match(await sendLetter(s, dir, ann, { to: "Bob", text: "2" }, T0 + MAIL_GAP - 1), /Wait/);
  for (let i = 1; i < MAIL_PER_HOUR; i++) assert.equal(await sendLetter(s, dir, ann, { to: "Bob", text: "x" }, T0 + i * MAIL_GAP), "");
  assert.match(await sendLetter(s, dir, ann, { to: "Bob", text: "x" }, T0 + MAIL_PER_HOUR * MAIL_GAP), /an hour/);
  assert.equal(await sendLetter(s, dir, ann, { to: "Bob", text: "x" }, T0 + 3600 + MAIL_GAP), "");
});

test("reading, deleting and paging", async () => {
  const s = new MemoryMailStore();
  for (let i = 0; i < MAIL_PAGE + 5; i++) await sendLetter(s, dir, ann, { to: "Bob", text: `n${i}` }, T0 + i * 130);
  const first = await page(s, "bob", "inbox");
  assert.equal(first.items.length, MAIL_PAGE);
  assert.equal(first.more, true);
  assert.equal(first.items[0].text, `n${MAIL_PAGE + 4}`);
  const second = await page(s, "bob", "inbox", first.items[MAIL_PAGE - 1].id);
  assert.equal(second.items.length, 5);
  assert.equal(second.more, false);
  assert.equal(second.items[4].text, "n0");
  // Only your own copy changes.
  assert.equal(await mailOrder(s, "bob", { action: "mail_read", folder: "inbox", ids: [first.items[0].id] }), "");
  assert.equal((await page(s, "bob", "inbox")).unread.inbox, MAIL_PAGE + 4);
  const annSent = (await page(s, "ann", "sent")).items[0].id;
  await mailOrder(s, "bob", { action: "mail_delete", folder: "inbox", ids: [annSent] });
  assert.equal((await page(s, "ann", "sent")).items[0].id, annSent);
  await mailOrder(s, "bob", { action: "mail_delete", folder: "inbox", ids: [first.items[0].id, "x", -1] });
  assert.equal((await page(s, "bob", "inbox")).items[0].text, `n${MAIL_PAGE + 3}`);
  assert.equal((await page(s, "ann", "sent")).items.length, MAIL_PAGE);
  await mailOrder(s, "bob", { action: "mail_read_all", folder: "inbox" });
  assert.equal((await page(s, "bob", "inbox")).unread.inbox, 0);
  assert.equal(await mailOrder(s, "bob", { action: "mail_read", folder: "junk", ids: [1] }), "Choose a folder.");
});

test("old letters go", async () => {
  const s = new MemoryMailStore();
  await sendLetter(s, dir, ann, { to: "Bob", text: "old" }, T0);
  await sendLetter(s, dir, cid, { to: "Bob", text: "new" }, T0 + MAIL_KEPT + 1);
  assert.deepEqual((await page(s, "bob", "inbox")).items.map((l) => l.text), ["new"]);
});

test("the reports inbox", async () => {
  const reports = [
    { id: 1, user: "bob", at: T0, report: { kind: "raid", role: "defender" } },
    { id: 2, user: "ann", at: T0, report: { kind: "spy", role: "spy", name: "Bob" } },
    { id: 3, user: "bob", at: T0 + 5, report: { kind: "spy", role: "target", name: "Ann" } },
  ];
  const s = new MemoryMailStore(reports);
  const view = await page(s, "bob", "reports");
  assert.deepEqual(view.items.map((r) => r.id), [3, 1]);
  assert.equal(view.items[0].read, false);
  assert.deepEqual(view.unread, { inbox: 0, reports: 2 });
  await mailOrder(s, "bob", { action: "mail_read", folder: "reports", ids: [3] });
  assert.equal((await page(s, "bob", "reports")).unread.reports, 1);
  await mailOrder(s, "bob", { action: "mail_delete", folder: "reports", ids: [1, 2] });
  assert.deepEqual((await page(s, "bob", "reports")).items.map((r) => r.id), [3]);
  assert.equal((await page(s, "ann", "reports")).items.length, 1);
  await mailOrder(s, "ann", { action: "mail_read_all", folder: "reports" });
  assert.equal((await page(s, "ann", "reports")).unread.reports, 0);
});
