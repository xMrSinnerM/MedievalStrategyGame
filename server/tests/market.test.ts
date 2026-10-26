// The market between players (supabase/functions/game/market.ts and the orders in game.ts).
//   node --test server/tests/*.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeRules } from "../rules/load.ts";
import { act, newPlayer, type PvpRules, type World } from "../../supabase/functions/game/game.ts";
import { CastleState } from "../rules/castle_state.ts";
import { goingRates, lotLimit, proceedsFor, type MarketRules, type Offer } from "../../supabase/functions/game/market.ts";

const root = new URL("../../", import.meta.url);
const json = (path: string) => JSON.parse(readFileSync(new URL(path, root), "utf8"));
const rules = makeRules(json("data/buildings.json"), json("data/units.json"), json("data/barons.json"));
const world: World = json("server/world/world.json");
const pvp: PvpRules = json("data/pvp.json");
const marketRules: MarketRules = json("data/market.json");
const T0 = 1_000_000;

function player(name = "Ann", keep = 2) {
  const p = newPlayer(rules, world, name, T0, world.spots[1], pvp);
  p.castle.resources = { wood: 900, stone: 900, food: 900, gold: 900 };
  const k = p.castle.buildings.find((b) => b.type === "keep")!;
  k.level = keep;
  return p;
}

const post = (p: ReturnType<typeof player>, req: Record<string, unknown>, open = 0) =>
  act(rules, p, { action: "post_offer", ...req }, T0, { market: { rules: marketRules, open } });

test("posting an offer", () => {
  const p = player();
  const ok = { give: "wood", give_amount: 400, want: "stone", want_amount: 500 };
  assert.equal(post(player("Ann", 1), ok).error, `The market opens at keep level ${marketRules.unlock_keep}.`);
  assert.equal(post(p, { ...ok, give: "gold" }).error, "Choose what to give.");
  assert.equal(post(p, { ...ok, want: "silk" }).error, "Choose what you want for it.");
  assert.equal(post(p, { ...ok, want: "wood" }).error, "Trade one good for another.");
  assert.equal(post(p, { ...ok, give_amount: 0 }).error, "Choose how much.");
  assert.equal(post(p, { ...ok, want_amount: 2.5 }).error, "Choose how much.");
  assert.equal(post(p, { ...ok, give_amount: 901 }).error, "You don't have that much wood.");
  assert.equal(post(p, { ...ok, want_amount: 801 }).error, "Ask between 0.5 and 2 stone for each wood.");
  assert.equal(post(p, { ...ok, want_amount: 199 }).error, "Ask between 0.5 and 2 stone for each wood.");
  assert.equal(post(p, ok, marketRules.max_offers).error, `You can have at most ${marketRules.max_offers} offers up at once.`);
  assert.equal(act(rules, p, { action: "post_offer", ...ok }, T0).error, "Unknown order.");
  const out = post(p, ok);
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.wood), 500);
  assert.deepEqual(out.offer, { seller_name: "Ann", give: "wood", give_amount: 400, want: "stone", want_amount: 500,
    proceeds: 475, posted: T0, expires: T0 + marketRules.offer_hours * 3600 });
  // The exact limits of the price are allowed.
  assert.equal(post(p, { ...ok, want_amount: 800 }).error, "");
  assert.equal(post(p, { ...ok, want_amount: 200 }).error, "");
});

test("one offer gives at most the lot limit for your keep", () => {
  const p = player();
  p.castle.resources.wood = 5000;
  const castle = CastleState.fromDict(rules.buildings, p.castle);
  const cap = lotLimit(castle, marketRules);
  assert.equal(cap, marketRules.lot_per_keep_level * 2);
  const castleRoom = castle.storageCapacity();
  const give = Math.min(cap + 1, Math.floor(castleRoom));
  if (give > cap) {
    assert.equal(post(p, { give: "wood", give_amount: give, want: "food", want_amount: give }).error, `One offer gives at most ${cap}.`);
  }
  assert.equal(post(p, { give: "wood", give_amount: Math.min(cap, 900), want: "food", want_amount: Math.min(cap, 900) }).error, "");
});

test("the market's cut", () => {
  assert.equal(proceedsFor(marketRules, 100), 95);
  assert.equal(proceedsFor(marketRules, 101), 95);
  assert.equal(proceedsFor(marketRules, 1), 0);
  assert.equal(proceedsFor(marketRules, 20), 19);
});

const offer: Offer = { id: 7, seller_name: "Bob", give: "stone", give_amount: 300, want: "food", want_amount: 400,
  proceeds: 380, posted: T0 - 10, expires: T0 + 3600 };
const buy = (p: ReturnType<typeof player>, o: Offer | undefined = offer, t = T0) =>
  act(rules, p, { action: "buy_offer", id: 7 }, t, { market: { rules: marketRules, offer: o } });

test("buying an offer", () => {
  const p = player();
  assert.equal(act(rules, p, { action: "buy_offer", id: 7 }, T0, { market: { rules: marketRules } }).error, "That offer is gone.");
  assert.equal(buy(p, offer, T0 + 3600).error, "That offer is gone.");
  assert.equal(buy(p, { ...offer, seller_name: "Ann" }).error, "That's your own offer.");
  assert.equal(buy(player("Ann", 1)).error, `The market opens at keep level ${marketRules.unlock_keep}.`);
  assert.equal(buy(p, { ...offer, want_amount: 901 }).error, "You don't have enough food.");
  const cap = CastleState.fromDict(rules.buildings, p.castle).storageCapacity();
  const full = player();
  full.castle.resources.stone = cap - 100;
  assert.equal(buy(full).error, "Your storage has no room for 300 more stone.");
  const out = buy(p);
  assert.equal(out.error, "");
  assert.equal(Math.round(out.state.castle.resources.food), 500);
  assert.equal(Math.round(out.state.castle.resources.stone), 1200);
  assert.deepEqual(out.marketReports, [{ kind: "market", event: "bought", at: T0, name: "Bob", give: "stone", give_amount: 300,
    want: "food", want_amount: 400 }]);
});

test("proceeds reach the seller's castle, up to its storage", () => {
  const p = player();
  const cap = CastleState.fromDict(rules.buildings, p.castle).storageCapacity();
  p.castle.resources.food = cap - 100;
  const out = act(rules, p, { action: "state" }, T0, { marketIncome: { food: 380, wood: 50 } });
  assert.equal(Math.round(out.state.castle.resources.food), Math.floor(cap));
  assert.equal(Math.round(out.state.castle.resources.wood), 950);
  assert.equal(out.marketReports?.length, 1);
  assert.equal(out.marketReports?.[0].event, "spilled");
  assert.ok((out.marketReports?.[0].lost?.food ?? 0) >= 280);
  const fine = act(rules, player(), { action: "state" }, T0, { marketIncome: { food: 10 } });
  assert.equal(fine.marketReports, undefined);
});

test("the going rates", () => {
  assert.deepEqual(goingRates([
    { give: "wood", give_amount: 100, want: "stone", want_amount: 150 },
    { give: "wood", give_amount: 300, want: "stone", want_amount: 300 },
    { give: "food", give_amount: 200, want: "wood", want_amount: 100 },
  ]), { "wood>stone": 1.13, "food>wood": 0.5 });
  assert.deepEqual(goingRates([]), {});
});
